CREATE OR ALTER PROCEDURE dbo.spAgregarDireccion
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdProvincia INT -- provincia
    , @inCanton NVARCHAR(64) -- cantón
    , @inDistrito NVARCHAR(64) -- distrito
    , @inOtrasSenas NVARCHAR(256) -- otras señas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP004 Agregar dirección de envío. Un cliente puede tener varias (restricción 2).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarDireccion
        @inIdUsuario = 2
        , @inIdProvincia = 1
        , @inCanton = N'Desamparados'
        , @inDistrito = N'San Miguel'
        , @inOtrasSenas = N'Higuito, 200 m sur de la iglesia, casa verde'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @canton NVARCHAR(64)
            , @distrito NVARCHAR(64)
            , @otrasSenas NVARCHAR(256)
            , @idDireccion INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @canton = NULLIF(LTRIM(RTRIM(@inCanton)), N'');
        SET @distrito = NULLIF(LTRIM(RTRIM(@inDistrito)), N'');
        SET @otrasSenas = NULLIF(LTRIM(RTRIM(@inOtrasSenas)), N'');

        -- validaciones
        -- GP004 restricción 1: provincia, cantón, distrito y otras señas son obligatorios
        IF (@inIdProvincia IS NULL)
            OR (@canton IS NULL)
            OR (@distrito IS NULL)
            OR (@otrasSenas IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Provincia AS PR
            WHERE (PR.IdProvincia = @inIdProvincia)
        )
        BEGIN
            SET @outResultCode = 50045; -- la provincia no existe
            RETURN;
        END;

        INSERT INTO dbo.Direccion (
            IdUsuario
            , IdProvincia
            , Canton
            , Distrito
            , OtrasSenas
            , FlagActivo
            , FechaCreacion
        )
        VALUES (
            @inIdUsuario
            , @inIdProvincia
            , @canton
            , @distrito
            , @otrasSenas
            , @true
            , GETDATE()
        );

        SET @idDireccion = SCOPE_IDENTITY();

        -- primer resultado: la dirección creada (GP012 flujo alterno: al guardarla
        -- se regresa a la selección con esta dirección)
        SELECT @idDireccion AS IdDireccion;

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
