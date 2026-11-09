CREATE OR ALTER PROCEDURE dbo.spListarNotificacionPendiente
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP019 Notificar al cliente el estado del pedido.
Lo llama un proceso del backend cada cierto tiempo (por ejemplo cada
minuto con setInterval): toma los correos pendientes, los envía con
Nodemailer y marca cada uno con spMarcarNotificacion.
Los que fallaron se reintentan hasta un máximo de intentos (flujo alternativo).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarNotificacionPendiente
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @false BIT = 0
            , @maxIntentos INT = 5 -- después de 5 fallos se deja de intentar
            , @tamanoLote INT = 20; -- cuántos correos se envían por vuelta

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        SELECT TOP (@tamanoLote)
            N.IdNotificacion
            , N.IdPedido
            , N.Correo
            , N.Asunto
            , N.Mensaje
            , N.Intentos
        FROM dbo.Notificacion AS N
        WHERE (N.FlagEnviado = @false)
            AND (N.Intentos < @maxIntentos)
        ORDER BY N.FechaCreacion
            , N.IdNotificacion; -- los más antiguos primero

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
