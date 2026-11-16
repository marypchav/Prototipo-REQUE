CREATE OR ALTER PROCEDURE dbo.spObtenerCredencialAdmin
    @inCorreo NVARCHAR(150) -- correo con el que inicia sesión la administradora
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI001 Inicio de sesión como administrador.
Devuelve el hash de la contraseña para que el backend lo compare con bcrypt
(SQL Server no trae bcrypt). Si el backend ve que la contraseña no coincide,
responde el mismo 50020, así no se revela si el correo existe o no.
El hash nunca se envía al navegador.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerCredencialAdmin
        @inCorreo = N'admin@capanni.com'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @correo NVARCHAR(150);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @correo = LOWER(NULLIF(LTRIM(RTRIM(@inCorreo)), N''));

        -- validaciones
        IF (@correo IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        -- GI001 flujo alternativo: credenciales incorrectas
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.Correo = @correo)
                AND (U.EsAdministrador = @true)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50020; -- correo o contraseña incorrectos
            RETURN;
        END;

        -- primer resultado: datos para crear la sesión
        SELECT U.IdUsuario
            , U.Nombre
            , U.Correo
            , U.PassHash
        FROM dbo.Usuario AS U
        WHERE (U.Correo = @correo)
            AND (U.EsAdministrador = @true)
            AND (U.FlagActivo = @true);

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
