CREATE OR ALTER PROCEDURE dbo.spRegistrarEnvioNotificacion
    @inIdNotificacion INT -- notificación que se intentó enviar
    , @inFlagEnviado BIT -- 1 = el correo salió, 0 = falló
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP019 postcondición 2: el envío queda registrado en el sistema.
Cada intento suma 1 a Intentos; si salió, se marca enviado con fecha y hora.
Los fallos (flujo alterno) quedan pendientes para el siguiente reintento.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spRegistrarEnvioNotificacion
        @inIdNotificacion = 1
        , @inFlagEnviado = 1
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
            FROM dbo.Notificacion AS N
            WHERE (N.IdNotificacion = @inIdNotificacion)
        )
        BEGIN
            SET @outResultCode = 50059; -- la notificación no existe
            RETURN;
        END;

        UPDATE dbo.Notificacion
        SET Intentos = Intentos + 1
            , FlagEnviado = CASE
                    WHEN (@inFlagEnviado = @true) THEN @true
                    ELSE FlagEnviado
                END
            , FechaEnvio = CASE
                    WHEN (@inFlagEnviado = @true) THEN GETDATE()
                    ELSE FechaEnvio
                END
        WHERE (IdNotificacion = @inIdNotificacion);

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
