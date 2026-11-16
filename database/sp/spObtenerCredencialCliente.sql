CREATE OR ALTER PROCEDURE dbo.spObtenerCredencialCliente
    @inCorreo NVARCHAR(200) -- correo con el que inicia sesión el cliente
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP002 Iniciar sesión del cliente. Igual que spObtenerCredencialAdmin:
devuelve el hash para que el backend lo compare con bcrypt. Si no coincide,
el backend responde el mismo 50020, sin decir cuál dato falló (flujo alterno).
GP002 restricción 3: solo busca cuentas de cliente (EsAdministrador = 0),
así una sesión de cliente nunca tiene permisos de administración.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerCredencialCliente
        @inCorreo = N'ana@correo.com'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @correo NVARCHAR(200);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @correo = LOWER(NULLIF(LTRIM(RTRIM(@inCorreo)), N''));

        -- validaciones
        IF (@correo IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.Correo = @correo)
                AND (U.EsAdministrador = @false)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50020; -- correo o contraseña incorrectos
            RETURN;
        END;

        -- primer resultado: datos para crear la sesión (el hash no va al navegador)
        SELECT U.IdUsuario
            , U.Nombre
            , U.Correo
            , U.PassHash
        FROM dbo.Usuario AS U
        WHERE (U.Correo = @correo)
            AND (U.EsAdministrador = @false)
            AND (U.FlagActivo = @true);

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
