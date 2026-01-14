namespace SimonOfHH.Kiota.Client;

using System.Security.Authentication;
using System.Text;

codeunit 87102 "Kiota API Authorization SOHH"
{
    var
        OAuth2: Codeunit OAuth2;
        Initialized: Boolean;
        TokenExpiry: DateTime;
        CustomHeaders: Dictionary of [Text, SecretText];
        TokenBufferSeconds: Integer;
        AccessToken: SecretText;
        ClientSecret: SecretText;
        ClientId: Text;
        Scope: Text;
        TokenEndpoint: Text;

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

    procedure AddAuthorizationHeaders(var Headers: HttpHeaders): Boolean
    var
        BearerToken: SecretText;
        HeaderName: Text;
    begin
        if not EnsureValidToken() then
            exit(false);

        // Add Bearer token
        BearerToken := SecretStrSubstNo('Bearer %1', AccessToken);
        if Headers.Contains('Authorization') then
            Headers.Remove('Authorization');
        Headers.Add('Authorization', BearerToken);

        // Add any custom headers (e.g., ST-App-Key for ServiceTitan)
        foreach HeaderName in CustomHeaders.Keys() do begin
            if Headers.Contains(HeaderName) then
                Headers.Remove(HeaderName);
            Headers.Add(HeaderName, CustomHeaders.Get(HeaderName));
        end;

        exit(true);
    end;

    procedure GetBearerToken(): SecretText
    var
        EmptyToken: SecretText;
    begin
        if not EnsureValidToken() then
            exit(EmptyToken);

        exit(SecretStrSubstNo('Bearer %1', AccessToken));
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
        TokenExpiresIn: Integer;
        TokenAcquireErr: Label 'Failed to acquire OAuth2 token from %1', Comment = '%1 = Token endpoint';
        NewAccessToken: SecretText;
    begin
        // Try custom Basic Auth token acquisition first (for APIs like TekMetric)
        if AcquireTokenWithBasicAuth(NewAccessToken) then begin
            AccessToken := NewAccessToken;
            // Default to 1 hour expiry if not provided
            TokenExpiry := CurrentDateTime() + (3600 * 1000);
            exit(true);
        end;

        // Fallback to standard OAuth2 client credentials flow
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
        TokenExpiry := CurrentDateTime() + (3600 * 1000);

        exit(true);
    end;

    local procedure AcquireTokenWithBasicAuth(var NewAccessToken: SecretText): Boolean
    var
        Client: HttpClient;
        Content: HttpContent;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        RequestMsg: HttpRequestMessage;
        ResponseMsg: HttpResponseMessage;
        ResponseJson: JsonObject;
        AccessTokenToken: JsonToken;
        ExpiresInToken: JsonToken;
        ResponseText: Text;
    begin
        // Create POST request to token endpoint
        RequestMsg.Method := 'POST';
        RequestMsg.SetRequestUri(TokenEndpoint);

        // Set Basic Auth using HttpClient.DefaultRequestHeaders
        Client.DefaultRequestHeaders.Add('Authorization', BuildBasicAuthHeader());

        // Add content with content-type header
        Content.WriteFrom('grant_type=client_credentials');
        Content.GetHeaders(ContentHeaders);
        if ContentHeaders.Contains('Content-Type') then
            ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/x-www-form-urlencoded');
        RequestMsg.Content(Content);

        // Send request
        if not Client.Send(RequestMsg, ResponseMsg) then
            exit(false);

        if not ResponseMsg.IsSuccessStatusCode() then
            exit(false);

        // Parse response
        ResponseMsg.Content.ReadAs(ResponseText);
        if not ResponseJson.ReadFrom(ResponseText) then
            exit(false);

        // Extract access token
        if not ResponseJson.Get('access_token', AccessTokenToken) then
            exit(false);

        NewAccessToken := AccessTokenToken.AsValue().AsText();

        // Extract expiry if available
        if ResponseJson.Get('expires_in', ExpiresInToken) then
            TokenExpiry := CurrentDateTime() + (ExpiresInToken.AsValue().AsInteger() * 1000);

        exit(true);
    end;

    local procedure BuildBasicAuthHeader(): SecretText
    var
        Base64Convert: Codeunit "Base64 Convert";
    begin
        // Return as "Basic {base64}"
        exit(SecretStrSubstNo('Basic %1', Base64Convert.ToBase64(SecretStrSubstNo('%1:%2', ClientId, ClientSecret))));
    end;

    procedure ClearToken()
    begin
        Clear(AccessToken);
        Clear(TokenExpiry);
    end;
}
