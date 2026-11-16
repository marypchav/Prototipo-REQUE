CREATE OR ALTER PROCEDURE dbo.spModificarCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdCarritoDetalle INT -- línea del carrito
    , @inCantidad INT -- nueva cantidad
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP009 Modificar carrito: cambia la cantidad de una línea. Para quitarla se
usa spQuitarDelCarrito. Si la cantidad no es válida o supera las
existencias, no se cambia nada y se conserva la anterior (flujo alterno 1).
Después el backend vuelve a llamar spListarCarrito para recalcular (restricción 2).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spModificarCarrito
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
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @existencias INT
            , @flagActivo BIT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        IF (@inCantidad IS NULL)
            OR (@inCantidad <= 0)
        BEGIN
            SET @outResultCode = 50046; -- cantidad inválida
            RETURN;
        END;

        -- la línea debe ser de este cliente
        SELECT @existencias = PT.Cantidad
            , @flagActivo = P.FlagActivo
        FROM dbo.CarritoDetalle AS CD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = CD.IdProductoTalla)
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        WHERE (CD.IdCarritoDetalle = @inIdCarritoDetalle)
            AND (CD.IdUsuario = @inIdUsuario);

        IF (@flagActivo IS NULL)
        BEGIN
            SET @outResultCode = 50049; -- el producto no está en el carrito
            RETURN;
        END;

        IF (@flagActivo <> @true)
        BEGIN
            SET @outResultCode = 50011; -- producto eliminado: solo se puede quitar
            RETURN;
        END;

        -- GP009 restricción 1: no puede superar las existencias
        IF (@inCantidad > @existencias)
        BEGIN
            SET @outResultCode = 50048; -- supera las existencias

            SELECT @existencias AS Existencias;
            RETURN;
        END;

        UPDATE dbo.CarritoDetalle
        SET Cantidad = @inCantidad
        WHERE (IdCarritoDetalle = @inIdCarritoDetalle)
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
