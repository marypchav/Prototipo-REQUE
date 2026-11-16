CREATE OR ALTER PROCEDURE dbo.spModificarDireccion
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdDireccion INT -- dirección que se modifica
    , @inIdProvincia INT -- provincia
    , @inCanton NVARCHAR(64) -- cantón
    , @inDistrito NVARCHAR(64) -- distrito
    , @inOtrasSenas NVARCHAR(256) -- otras señas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP005 Modificar dirección de envío. Mismas validaciones que GP004
(restricción 1). Solo el dueño la puede modificar (restricción 2): si la
dirección es de otro cliente se responde "no existe", sin revelar nada.
Restricción 3: los pedidos guardan una copia en texto de la dirección
(Pedido.DireccionEntrega), así que este cambio no los afecta.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spModificarDireccion
        @inIdUsuario = 2
        , @inIdDireccion = 1
        , @inIdProvincia = 1
        , @inCanton = N'Desamparados'
        , @inDistrito = N'San Miguel'
        , @inOtrasSenas = N'Higuito, 300 m sur de la iglesia, portón negro'
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
            , @otrasSenas NVARCHAR(256);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @canton = NULLIF(LTRIM(RTRIM(@inCanton)), N'');
        SET @distrito = NULLIF(LTRIM(RTRIM(@inDistrito)), N'');
        SET @otrasSenas = NULLIF(LTRIM(RTRIM(@inOtrasSenas)), N'');

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Direccion AS D
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50044; -- la dirección no existe
            RETURN;
        END;

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

        UPDATE dbo.Direccion
        SET IdProvincia = @inIdProvincia
            , Canton = @canton
            , Distrito = @distrito
            , OtrasSenas = @otrasSenas
        WHERE (IdDireccion = @inIdDireccion)
            AND (IdUsuario = @inIdUsuario);

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
