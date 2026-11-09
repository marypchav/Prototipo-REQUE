CREATE OR ALTER PROCEDURE dbo.spAgregarDireccion
    @inIdUsuario INT -- cliente dueño de la dirección
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProvincia INT -- provincia
    , @inCanton NVARCHAR(64) -- cantón
    , @inDistrito NVARCHAR(64) -- distrito
    , @inOtrasSenas NVARCHAR(256) -- otras señas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP004 Agregar dirección de envío.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarDireccion
        @inIdUsuario = 2
        , @inIP = '127.0.0.1'
        , @inIdProvincia = 1
        , @inCanton = N'Desamparados'
        , @inDistrito = N'San Miguel'
        , @inOtrasSenas = N'200 m sur de la iglesia, casa verde'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @tipoOperacionAgregar INT = 7; -- TipoOperacion "Agregar dirección"

        -- variables de uso general
        DECLARE @canton NVARCHAR(64)
            , @distrito NVARCHAR(64)
            , @otrasSenas NVARCHAR(256);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @canton = LTRIM(RTRIM(ISNULL(@inCanton, N'')));
        SET @distrito = LTRIM(RTRIM(ISNULL(@inDistrito, N'')));
        SET @otrasSenas = LTRIM(RTRIM(ISNULL(@inOtrasSenas, N'')));

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

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Provincia AS PR
            WHERE (PR.IdProvincia = @inIdProvincia)
        )
        BEGIN
            SET @outResultCode = 50013; -- provincia no existe
            RETURN;
        END;

        -- GP004 restricción 1: todos los campos son obligatorios
        IF (@canton = N'')
            OR (@distrito = N'')
            OR (@otrasSenas = N'')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        -- variables para la transacción
        DECLARE @idDireccion INT
            , @jsonDespues NVARCHAR(MAX);

        -- transacción: dirección y bitácora van juntas
        BEGIN TRANSACTION tAgregarDireccion;

            INSERT INTO dbo.Direccion (
                IdUsuario
                , IdProvincia
                , Canton
                , Distrito
                , OtrasSenas
            )
            VALUES (
                @inIdUsuario
                , @inIdProvincia
                , @canton
                , @distrito
                , @otrasSenas
            );

            SET @idDireccion = SCOPE_IDENTITY();
            SET @jsonDespues = dbo.fnJsonDireccion(@idDireccion);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionAgregar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tAgregarDireccion;

        -- resultado para la capa lógica (GP012 la puede preseleccionar)
        SELECT @idDireccion AS IdDireccion;

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
