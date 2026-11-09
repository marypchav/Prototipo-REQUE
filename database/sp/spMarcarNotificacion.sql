CREATE OR ALTER PROCEDURE dbo.spMarcarNotificacion
    @inIdNotificacion INT -- notificación que se procesó
    , @inFlagEnviado BIT -- 1 = el correo salió bien, 0 = falló
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP019: registra el resultado del envío de un correo.
Si salió bien queda marcado con su fecha; si falló se suma un intento para
reintentarlo en la siguiente vuelta (flujo alternativo). En ambos casos el
nuevo estado ya es visible para el cliente en su historial.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spMarcarNotificacion
        @inIdNotificacion = 1
        , @inFlagEnviado = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Notificacion AS N
            WHERE (N.IdNotificacion = @inIdNotificacion)
                AND (N.FlagEnviado = @false)
        )
        BEGIN
            SET @outResultCode = 50027; -- no existe o ya estaba enviada
            RETURN;
        END;

        BEGIN TRANSACTION tMarcarNotificacion;

            UPDATE dbo.Notificacion
            SET FlagEnviado = ISNULL(@inFlagEnviado, @false)
                , FechaEnvio = CASE
                    WHEN (@inFlagEnviado = @true) THEN GETDATE()
                    ELSE NULL
                  END
                , Intentos = Intentos + 1
            WHERE (IdNotificacion = @inIdNotificacion);

        COMMIT TRANSACTION tMarcarNotificacion;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
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
