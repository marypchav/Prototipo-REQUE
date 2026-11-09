CREATE OR ALTER PROCEDURE dbo.spListarDireccion
    @inIdUsuario INT -- cliente dueño de las direcciones
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP003 Visualizar dirección de envío.
Cada cliente solo ve sus propias direcciones activas (restricción 1).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarDireccion
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

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

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
        ORDER BY D.FechaCreacion DESC;

    END TRY
    BEGIN CATCH

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
