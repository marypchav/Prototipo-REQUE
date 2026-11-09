CREATE OR ALTER PROCEDURE dbo.spActualizarCarrito
    @inIdUsuario INT -- cliente dueño del carrito
    , @inIdCarritoDetalle INT -- línea del carrito que se cambia
    , @inCantidad INT -- nueva cantidad; 0 = quitar el producto del carrito
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP009 Modificar carrito (cambiar cantidad o quitar un producto).
El total se recalcula llamando después a spListarCarrito.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarCarrito
        @inIdUsuario = 2
        , @inIdCarritoDetalle = 1
        , @inCantidad = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @cantidadQuitar INT = 0;

        -- variables de uso general
        DECLARE @existencias INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @existencias = NULL;

        -- validaciones
        -- la línea debe existir y ser del cliente
        SELECT @existencias = PT.Cantidad
        FROM dbo.CarritoDetalle AS CD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = CD.IdProductoTalla)
        WHERE (CD.IdCarritoDetalle = @inIdCarritoDetalle)
            AND (CD.IdUsuario = @inIdUsuario);

        IF (@existencias IS NULL)
        BEGIN
            SET @outResultCode = 50018; -- línea del carrito no existe
            RETURN;
        END;

        IF (@inCantidad IS NULL)
            OR (@inCantidad < @cantidadQuitar)
        BEGIN
            SET @outResultCode = 50009; -- cantidad inválida
            RETURN;
        END;

        -- GP009 restricción 1: no puede superar las existencias.
        -- quitar (0) siempre se permite, aunque el producto ya no exista
        IF (@inCantidad > @cantidadQuitar)
            AND (@inCantidad > @existencias)
        BEGIN
            SET @outResultCode = 50016; -- existencias insuficientes
            RETURN;
        END;

        -- transacción. Sin IF: el WHERE de cada sentencia decide cuál aplica
        BEGIN TRANSACTION tActualizarCarrito;

            DELETE FROM dbo.CarritoDetalle
            WHERE (IdCarritoDetalle = @inIdCarritoDetalle)
                AND (@inCantidad = @cantidadQuitar);

            UPDATE dbo.CarritoDetalle
            SET Cantidad = @inCantidad
            WHERE (IdCarritoDetalle = @inIdCarritoDetalle)
                AND (@inCantidad > @cantidadQuitar);

        COMMIT TRANSACTION tActualizarCarrito;

        -- resultado para la capa lógica: indicador del carrito.
        -- 0 = el carrito quedó vacío (GP009 flujo alternativo)
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
