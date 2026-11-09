CREATE OR ALTER PROCEDURE dbo.spRegistrarCliente
    @inNombre NVARCHAR(100) -- nombre completo
    , @inCorreo VARCHAR(128) -- correo, se usa para iniciar sesión
    , @inTelefono VARCHAR(16) -- teléfono de 8 dígitos
    , @inPassHash VARCHAR(100) -- hash bcrypt generado en Node (nunca el password)
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP001 Registrar cliente.
El largo mínimo de 8 caracteres del password se valida en Node antes de
generar el hash: aquí ya solo llega el hash.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spRegistrarCliente
        @inNombre = N'Ana Mora Solís'
        , @inCorreo = 'ana@gmail.com'
        , @inTelefono = '88112233'
        , @inPassHash = '$2b$10$hashDePrueba'
        , @inIP = '127.0.0.1'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @tipoOperacionRegistrar INT = 1 -- TipoOperacion "Registrar cliente"
            , @largoTelefono INT = 8;

        -- variables de uso general
        DECLARE @nombre NVARCHAR(100)
            , @correo VARCHAR(128)
            , @telefono VARCHAR(16)
            , @passHash VARCHAR(100);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- se limpian espacios; el correo se guarda en minúscula para que
        -- "Ana@Gmail.com" y "ana@gmail.com" cuenten como el mismo
        SET @nombre = LTRIM(RTRIM(ISNULL(@inNombre, '')));
        SET @correo = LOWER(LTRIM(RTRIM(ISNULL(@inCorreo, ''))));
        SET @telefono = LTRIM(RTRIM(ISNULL(@inTelefono, '')));
        SET @passHash = ISNULL(@inPassHash, '');

        -- validaciones
        -- campos obligatorios
        IF (@nombre = '')
            OR (@passHash = '')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        -- correo con formato básico algo@algo.algo y sin espacios
        IF (@correo NOT LIKE '%_@_%._%')
            OR (@correo LIKE '% %')
        BEGIN
            SET @outResultCode = 50004; -- correo inválido
            RETURN;
        END;

        -- teléfono de 8 dígitos
        IF (LEN(@telefono) <> @largoTelefono)
            OR (@telefono LIKE '%[^0-9]%')
        BEGIN
            SET @outResultCode = 50006; -- teléfono inválido
            RETURN;
        END;

        -- correo único (GP001 restricción 2)
        IF EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.Correo = @correo)
        )
        BEGIN
            SET @outResultCode = 50005; -- correo ya registrado
            RETURN;
        END;

        -- variables para la transacción
        DECLARE @idUsuario INT
            , @jsonDespues NVARCHAR(MAX);

        -- transacción: el usuario y su registro en bitácora van juntos
        BEGIN TRANSACTION tRegistrarCliente;

            INSERT INTO dbo.Usuario (
                Nombre
                , Correo
                , Telefono
                , PassHash
            )
            VALUES (
                @nombre
                , @correo
                , @telefono
                , @passHash
            );

            SET @idUsuario = SCOPE_IDENTITY();

            -- JSON sin el hash: la bitácora nunca guarda credenciales
            SET @jsonDespues = (
                SELECT @idUsuario AS IdUsuario
                    , @nombre AS Nombre
                    , @correo AS Correo
                    , @telefono AS Telefono
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @idUsuario
                , @tipoOperacionRegistrar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tRegistrarCliente;

        -- resultado para la capa lógica
        SELECT @idUsuario AS IdUsuario;

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

        -- 2627/2601 = violó el UNIQUE del correo (dos registros simultáneos)
        SET @outResultCode = CASE
                WHEN (ERROR_NUMBER() IN (2627, 2601)) THEN 50005
                ELSE 50000 -- error inesperado
            END;

    END CATCH;

    SET NOCOUNT OFF;
END;
GO
