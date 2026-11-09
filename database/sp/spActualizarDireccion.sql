CREATE OR ALTER PROCEDURE dbo.spActualizarDireccion
    @inIdUsuario INT -- cliente que edita (debe ser el dueño)
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdDireccion INT -- dirección que se edita
    , @inIdProvincia INT -- nueva provincia
    , @inCanton NVARCHAR(64) -- nuevo cantón
    , @inDistrito NVARCHAR(64) -- nuevo distrito
    , @inOtrasSenas NVARCHAR(256) -- nuevas otras señas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP005 Modificar dirección de envío.
Los pedidos ya hechos no cambian porque guardan una copia de la dirección
en texto (Pedido.DireccionEntrega).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarDireccion
        @inIdUsuario = 2
        , @inIP = '127.0.0.1'
        , @inIdDireccion = 1
        , @inIdProvincia = 1
        , @inCanton = N'Desamparados'
        , @inDistrito = N'Higuito'
        , @inOtrasSenas = N'Frente a la plaza, portón negro'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionModificar INT = 8; -- TipoOperacion "Modificar dirección"

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
        -- GP005 restricción 2: solo el dueño puede modificarla
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Direccion AS D
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50014; -- dirección no existe o no es del cliente
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

        IF (@canton = N'')
            OR (@distrito = N'')
            OR (@otrasSenas = N'')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @huboCambio BIT
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SET @huboCambio = @false;

        SELECT @huboCambio = CASE
                WHEN (D.IdProvincia <> @inIdProvincia)
                    OR (D.Canton <> @canton)
                    OR (D.Distrito <> @distrito)
                    OR (D.OtrasSenas <> @otrasSenas)
                THEN @true
                ELSE @false
              END
        FROM dbo.Direccion AS D
        WHERE (D.IdDireccion = @inIdDireccion);

        -- si no cambió nada se sale con éxito y no se registra en bitácora
        IF (@huboCambio = @false)
        BEGIN
            RETURN;
        END;

        SET @jsonAntes = dbo.fnJsonDireccion(@inIdDireccion);

        -- transacción: cambio y bitácora van juntos
        BEGIN TRANSACTION tActualizarDireccion;

            UPDATE dbo.Direccion
            SET IdProvincia = @inIdProvincia
                , Canton = @canton
                , Distrito = @distrito
                , OtrasSenas = @otrasSenas
            WHERE (IdDireccion = @inIdDireccion);

            SET @jsonDespues = dbo.fnJsonDireccion(@inIdDireccion);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionModificar
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarDireccion;

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
