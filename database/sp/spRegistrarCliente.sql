CREATE OR ALTER PROCEDURE dbo.spRegistrarCliente
    @inNombre NVARCHAR(100) -- nombre completo
    , @inCorreo NVARCHAR(200) -- correo (se valida formato y largo máximo de 128)
    , @inTelefono NVARCHAR(30) -- teléfono; se le quitan espacios y guiones
    , @inPassHash VARCHAR(100) -- hash bcrypt que calcula el backend
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP001 Registrar cliente. El perfil se crea con rol de cliente
(EsAdministrador = 0, postcondición 1).
GP001 restricción 3: el largo mínimo de 8 caracteres lo valida el backend
ANTES de calcular el hash (aquí ya solo llega el hash, código 50043).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spRegistrarCliente
        @inNombre = N'Ana Mora Solís'
        , @inCorreo = N'ana@correo.com'
        , @inTelefono = N'8888-1234'
        , @inPassHash = '$2b$10$abcdefghijklmnopqrstuuJr7v3v4Yp0bW3E3l1E2f1nZ1q0m2e4a'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @largoMaxCorreo INT = 128
            , @largoMinTelefono INT = 8
            , @largoMaxTelefono INT = 16;

        -- variables de uso general
        DECLARE @nombre NVARCHAR(100)
            , @correo NVARCHAR(200)
            , @telefono NVARCHAR(30)
            , @passHash VARCHAR(100)
            , @idUsuario INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @nombre = NULLIF(LTRIM(RTRIM(@inNombre)), N'');
        SET @correo = LOWER(NULLIF(LTRIM(RTRIM(@inCorreo)), N''));
        SET @telefono = NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(@inTelefono)), N' ', N''), N'-', N''), N'');
        SET @passHash = NULLIF(LTRIM(RTRIM(@inPassHash)), '');

        -- validaciones
        -- GP001 restricción 1: no se pueden dejar campos vacíos
        IF (@nombre IS NULL)
            OR (@correo IS NULL)
            OR (@telefono IS NULL)
            OR (@passHash IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        -- GP001 restricción 2: formato de correo (texto@texto.texto, una sola @, sin espacios)
        IF (@correo NOT LIKE N'%_@_%._%')
            OR (@correo LIKE N'%[ ,;:<>()]%')
            OR ((LEN(@correo) - LEN(REPLACE(@correo, N'@', N''))) <> 1)
            OR (LEN(@correo) > @largoMaxCorreo)
        BEGIN
            SET @outResultCode = 50040; -- correo con formato inválido
            RETURN;
        END;

        -- teléfono: solo dígitos (con + opcional al inicio), de 8 a 16
        IF (REPLACE(@telefono, N'+', N'') LIKE N'%[^0-9]%')
            OR (CHARINDEX(N'+', @telefono) > 1)
            OR (LEN(@telefono) NOT BETWEEN @largoMinTelefono AND @largoMaxTelefono)
        BEGIN
            SET @outResultCode = 50042; -- teléfono inválido
            RETURN;
        END;

        -- GP001 restricción 2 y flujo alterno 4: correo único
        IF EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.Correo = @correo)
        )
        BEGIN
            SET @outResultCode = 50041; -- correo ya registrado
            RETURN;
        END;

        INSERT INTO dbo.Usuario (
            Nombre
            , Correo
            , Telefono
            , PassHash
            , EsAdministrador
            , FlagActivo
            , FechaCreacion
        )
        VALUES (
            @nombre
            , @correo
            , @telefono
            , @passHash
            , @false -- rol de cliente final
            , @true
            , GETDATE()
        );

        SET @idUsuario = SCOPE_IDENTITY();

        -- primer resultado: el usuario creado
        SELECT @idUsuario AS IdUsuario;

    END TRY
    BEGIN CATCH

        -- dos registros al mismo tiempo con el mismo correo: lo detiene
        -- UQ_Usuario_Correo. No es un error del sistema, es el flujo alterno 4
        IF (ERROR_NUMBER() IN (2601, 2627))
        BEGIN
            SET @outResultCode = 50041; -- correo ya registrado
        END
        ELSE
        BEGIN
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
        END;

    END CATCH;

    SET NOCOUNT OFF;
END;
GO
