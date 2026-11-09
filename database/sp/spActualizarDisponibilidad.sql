CREATE OR ALTER PROCEDURE dbo.spActualizarDisponibilidad
    @inIdUsuario INT -- quién actualiza, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProducto INT -- producto
    , @inIdTalla INT -- talla que se ajusta
    , @inCantidad INT -- nueva cantidad disponible (entero >= 0)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI007 Actualizar disponibilidad del producto.
Si el producto todavía no tenía esa talla, se agrega; si ya la tenía, se
reemplaza la cantidad. Cantidad 0 = agotado en esa talla (GI007 postcondición 2).
El UPDATE bloquea la fila: si un cliente confirma una orden de esa misma
talla al mismo tiempo, una operación espera a la otra (GI007 restricción 2).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarDisponibilidad
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdProducto = 1
        , @inIdTalla = 4
        , @inCantidad = 3
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionDisponibilidad INT = 5; -- "Actualizar disponibilidad"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @cantidadActual INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @cantidadActual = NULL; -- NULL = el producto no tenía esa talla

        -- validaciones
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Producto AS P
            WHERE (P.IdProducto = @inIdProducto)
                AND (P.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o fue eliminado
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Talla AS T
            WHERE (T.IdTalla = @inIdTalla)
        )
        BEGIN
            SET @outResultCode = 50010; -- talla inválida
            RETURN;
        END;

        -- GI007 restricción 1: entero mayor o igual que cero
        IF (@inCantidad IS NULL)
            OR (@inCantidad < 0)
        BEGIN
            SET @outResultCode = 50009; -- cantidad inválida
            RETURN;
        END;

        -- preprocesamiento
        SELECT @cantidadActual = PT.Cantidad
        FROM dbo.ProductoTalla AS PT
        WHERE (PT.IdProducto = @inIdProducto)
            AND (PT.IdTalla = @inIdTalla);

        -- si la cantidad no cambia, éxito sin tocar nada
        IF (@cantidadActual = @inCantidad)
        BEGIN
            RETURN;
        END;

        -- variables para la transacción
        DECLARE @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        SET @jsonAntes = dbo.fnJsonProducto(@inIdProducto);

        -- transacción. Sin IF: el WHERE de cada sentencia decide cuál aplica
        BEGIN TRANSACTION tActualizarDisponibilidad;

            -- la talla ya existía: se reemplaza la cantidad
            UPDATE dbo.ProductoTalla
            SET Cantidad = @inCantidad
            WHERE (IdProducto = @inIdProducto)
                AND (IdTalla = @inIdTalla);

            -- la talla no existía: se agrega
            INSERT INTO dbo.ProductoTalla (
                IdProducto
                , IdTalla
                , Cantidad
            )
            SELECT @inIdProducto
                , @inIdTalla
                , @inCantidad
            WHERE (@cantidadActual IS NULL);

            SET @jsonDespues = dbo.fnJsonProducto(@inIdProducto);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionDisponibilidad
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarDisponibilidad;

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
