CREATE OR ALTER FUNCTION dbo.fnJsonDireccion (
    @inIdDireccion INT -- dirección de la que se arma el JSON
)
RETURNS NVARCHAR(MAX)
AS
/*
Devuelve el estado completo de una dirección en JSON, para la bitácora.

Ejemplo:
    SELECT dbo.fnJsonDireccion(1) AS Json;
*/
BEGIN
    DECLARE @json NVARCHAR(MAX);

    SET @json = (
        SELECT D.IdDireccion
            , D.IdUsuario
            , PR.Nombre AS Provincia
            , D.Canton
            , D.Distrito
            , D.OtrasSenas
            , D.FlagActivo
        FROM dbo.Direccion AS D
        INNER JOIN dbo.Provincia AS PR
            ON (PR.IdProvincia = D.IdProvincia)
        WHERE (D.IdDireccion = @inIdDireccion)
        FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
    );

    RETURN @json;
END;
GO
