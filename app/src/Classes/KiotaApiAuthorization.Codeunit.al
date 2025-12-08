namespace SimonOfHH.Kiota.Client;

using System.Security.Authentication;

codeunit 87102 "Kiota API Authorization SOHH"
{
    var
        OAuth2: Codeunit OAuth2;
        ClientId: Text;
        ClientSecret: SecretText;
        TokenEndpoint: Text;
        Scope: Text;
        AccessToken: SecretText;
        TokenExpiry: DateTime;
        CustomHeaders: Dictionary of [Text, SecretText];
        Initialized: Boolean;
        TokenBufferSeconds: Integer;

    procedure SetClientCredentials(NewClientId: Text; NewClientSecret: SecretText)
    begin
        ClientId := NewClientId;
        ClientSecret := NewClientSecret;
        TokenBufferSeconds := 60; // Refresh token 60 seconds before expiry
    end;

    procedure SetTokenEndpoint(NewTokenEndpoint: Text)
    begin
        TokenEndpoint := NewTokenEndpoint;
        Initialized := true;
    end;

    procedure SetScope(NewScope: Text)
    begin
        Scope := NewScope;
    end;

    procedure AddHeader(HeaderName: Text; HeaderValue: SecretText)
    begin
        if CustomHeaders.ContainsKey(HeaderName) then
            CustomHeaders.Set(HeaderName, HeaderValue)
        else
            CustomHeaders.Add(HeaderName, HeaderValue);
    end;

    procedure IsInitialized(): Boolean
    begin
        exit(Initialized and (ClientId <> '') and (TokenEndpoint <> ''));
    end;

    procedure AddBearerAuthorization(var Client: HttpClient)
    var
        Headers: HttpHeaders;
        HeaderName: Text;
    begin
        if not EnsureValidToken() then
            exit;

        Client.DefaultRequestHeaders().Add('Authorization', SecretStrSubstNo('Bearer %1', AccessToken));

        // Add any custom headers (e.g., ST-App-Key for ServiceTitan)
        foreach HeaderName in CustomHeaders.Keys() do
            Client.DefaultRequestHeaders().Add(HeaderName, CustomHeaders.Get(HeaderName));
    end;

    local procedure EnsureValidToken(): Boolean
    begin
        if IsTokenValid() then
            exit(true);

        exit(AcquireToken());
    end;

    local procedure IsTokenValid(): Boolean
    begin
        if AccessToken.IsEmpty() then
            exit(false);

        // Check if token is about to expire (with buffer)
        if CurrentDateTime() >= (TokenExpiry - (TokenBufferSeconds * 1000)) then
            exit(false);

        exit(true);
    end;

    local procedure AcquireToken(): Boolean
    var
        NewAccessToken: SecretText;
        TokenExpiresIn: Integer;
        TokenAcquireErr: Label 'Failed to acquire OAuth2 token from %1', Comment = '%1 = Token endpoint';
    begin
        // Use BC's built-in OAuth2 codeunit for client credentials flow
        if not OAuth2.AcquireTokenWithClientCredentials(
            ClientId,
            ClientSecret,
            TokenEndpoint,
            '',  // RedirectURL not needed for client credentials
            Scope,
            NewAccessToken)
        then
            Error(TokenAcquireErr, TokenEndpoint);

        AccessToken := NewAccessToken;
        // Default to 1 hour expiry if not provided (ServiceTitan tokens typically last 1 hour)
        TokenExpiry := CurrentDateTime() + (3600 * 1000);

        exit(true);
    end;

    procedure ClearToken()
    begin
        Clear(AccessToken);
        Clear(TokenExpiry);
    end;
}
