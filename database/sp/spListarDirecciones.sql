CREATE OR ALTER PROCEDURE dbo.spListarDirecciones
    @inIdUsuario INT -- cliente con sesión iniciada
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP003 Visualizar dirección de envío. Solo devuelve las direcciones del
cliente que pide (restricción 1). También sirve para llenar el formulario
de GP005 con los datos actuales.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarDirecciones
        @inIdUsuario = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: direcciones activas del cliente (vacío = flujo alterno
        -- "Aún no tiene direcciones registradas")
        SELECT D.IdDireccion
            , D.IdProvincia
            , PR.Nombre AS Provincia
            , D.Canton
            , D.Distrito
            , D.OtrasSenas
        FROM dbo.Direccion AS D
        INNER JOIN dbo.Provincia AS PR
            ON (PR.IdProvincia = D.IdProvincia)
        WHERE (D.IdUsuario = @inIdUsuario)
            AND (D.FlagActivo = @true)
        ORDER BY D.FechaCreacion DESC
            , D.IdDireccion DESC;

        -- segundo resultado: provincias para el formulario de GP004 y GP005
        SELECT PR.IdProvincia
            , PR.Nombre
        FROM dbo.Provincia AS PR
        ORDER BY PR.IdProvincia;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO
