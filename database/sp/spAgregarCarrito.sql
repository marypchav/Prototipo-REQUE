CREATE OR ALTER PROCEDURE dbo.spAgregarCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdProductoTalla INT -- producto y talla elegidos
    , @inCantidad INT -- cantidad a agregar (entero > 0)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP007 Agregar productos al carrito.
No reserva existencias (restricción 3): eso se garantiza en spConfirmarOrden.
Si el producto y la talla ya estaban en el carrito, se suma la cantidad
sin superar las existencias (flujo alternativo).
Devuelve el total de artículos para el indicador del carrito.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarCarrito
        @inIdUsuario = 2
        , @inIdProductoTalla = 1
        , @inCantidad = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @existencias INT
            , @enCarrito INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @existencias = NULL;
        SET @enCarrito = 0;

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

        -- GP007 restricción 2: entero positivo
        IF (@inCantidad IS NULL)
            OR (@inCantidad <= 0)
        BEGIN
            SET @outResultCode = 50009; -- cantidad inválida
            RETURN;
        END;

        -- la talla debe existir y su producto no estar eliminado
        SELECT @existencias = PT.Cantidad
        FROM dbo.ProductoTalla AS PT
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        WHERE (PT.IdProductoTalla = @inIdProductoTalla)
            AND (P.FlagActivo = @true);

        IF (@existencias IS NULL)
        BEGIN
            SET @outResultCode = 50015; -- producto o talla no existe
            RETURN;
        END;

        -- lo que ya tenía en el carrito de esa talla
        SELECT @enCarrito = CD.Cantidad
        FROM dbo.CarritoDetalle AS CD
        WHERE (CD.IdUsuario = @inIdUsuario)
            AND (CD.IdProductoTalla = @inIdProductoTalla);

        -- no puede pedir más de lo que hay (incluye agotados: existencias 0)
        IF ((@enCarrito + @inCantidad) > @existencias)
        BEGIN
            SET @outResultCode = 50016; -- existencias insuficientes
            RETURN;
        END;

        -- transacción. Sin IF: el WHERE de cada sentencia decide cuál aplica
        BEGIN TRANSACTION tAgregarCarrito;

            -- ya estaba en el carrito: se suma
            UPDATE dbo.CarritoDetalle
            SET Cantidad = Cantidad + @inCantidad
            WHERE (IdUsuario = @inIdUsuario)
                AND (IdProductoTalla = @inIdProductoTalla);

            -- no estaba: se agrega
            INSERT INTO dbo.CarritoDetalle (
                IdUsuario
                , IdProductoTalla
                , Cantidad
            )
            SELECT @inIdUsuario
                , @inIdProductoTalla
                , @inCantidad
            WHERE (@enCarrito = 0);

        COMMIT TRANSACTION tAgregarCarrito;

        -- resultado para la capa lógica: indicador del carrito
        SELECT ISNULL(SUM(CD.Cantidad), 0) AS CantidadArticulos
        FROM dbo.CarritoDetalle AS CD
        WHERE (CD.IdUsuario = @inIdUsuario);

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
