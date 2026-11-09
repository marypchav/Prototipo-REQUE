CREATE OR ALTER PROCEDURE dbo.spObtenerUsuarioLogin
    @inCorreo VARCHAR(128) -- correo con el que intenta ingresar
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI001 y GP002 Iniciar sesión.
Con bcrypt la comparación del password no se puede hacer en SQL: este SP
devuelve el hash y Node lo compara con bcrypt.compare(). Si no coincide,
Node responde el mismo mensaje que cuando el correo no existe (GP002: no se
dice cuál dato falló). El hash nunca se manda al navegador.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerUsuarioLogin
        @inCorreo = 'admin@capanni.com'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @idUsuario INT; -- queda en NULL si no hay coincidencia

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @idUsuario = NULL;

        -- validaciones
        SELECT @idUsuario = U.IdUsuario
        FROM dbo.Usuario AS U
        WHERE (U.Correo = LOWER(LTRIM(RTRIM(@inCorreo))))
            AND (U.FlagActivo = @true);

        IF (@idUsuario IS NULL)
        BEGIN
            SET @outResultCode = 50001; -- credenciales incorrectas
            RETURN;
        END;

        -- datos del usuario con el hash, solo para que Node lo compare
        SELECT U.IdUsuario
            , U.Nombre
            , U.Correo
            , U.PassHash
            , U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @idUsuario);

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
