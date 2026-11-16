CREATE OR ALTER PROCEDURE dbo.spListarNotificacionesPendientes
    @inMaxIntentos INT -- después de esta cantidad de fallos ya no se reintenta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP019 flujo alterno: si no se pudo enviar el correo, se reintenta.
El backend llama este SP cada cierto tiempo (por ejemplo, cada minuto) y
envía los correos que siguen pendientes. El estado del pedido igual es
visible en el historial aunque el correo falle.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarNotificacionesPendientes
        @inMaxIntentos = 5
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @false BIT = 0
            , @intentosPorDefecto INT = 5;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: correos por enviar, los más viejos primero
        SELECT N.IdNotificacion
            , N.IdPedido
            , N.Correo
            , N.Asunto
            , N.Mensaje
            , N.Intentos
        FROM dbo.Notificacion AS N
        WHERE (N.FlagEnviado = @false)
            AND (N.Intentos < ISNULL(@inMaxIntentos, @intentosPorDefecto))
        ORDER BY N.FechaCreacion
            , N.IdNotificacion;

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
