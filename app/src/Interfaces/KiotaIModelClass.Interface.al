namespace SimonOfHH.Kiota.Definitions;

interface "Kiota IModelClass SOHH"
{
    Access = public;
    procedure SetBody(NewJsonBody: JsonObject);
    procedure ToJson(): JsonObject;
}