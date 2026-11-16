CREATE OR ALTER PROCEDURE dbo.spAgregarAlCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdProductoTalla INT -- producto + talla elegida en el detalle
    , @inCantidad INT -- cantidad a agregar
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP007 Agregar productos al carrito. No reserva ni toca el inventario
(restricción 3, postcondición 2): las existencias se garantizan en GP014.
Si el producto y la talla ya estaban en el carrito, suma la cantidad sin
superar las existencias (flujo alterno 2). Si las supera, no agrega nada y
devuelve cuántas hay y cuántas tiene ya en el carrito, para el mensaje.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarAlCarrito
        @inIdUsuario = 2
        , @inIdProductoTalla = 5
        , @inCantidad = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @sinExistencias INT = 0;

        -- variables de uso general
        DECLARE @existencias INT
            , @enCarrito INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        -- GP007 restricción 2: entero positivo (el backend manda NULL si no es entero)
        IF (@inCantidad IS NULL)
            OR (@inCantidad <= 0)
        BEGIN
            SET @outResultCode = 50046; -- cantidad inválida
            RETURN;
        END;

        SELECT @existencias = PT.Cantidad
        FROM dbo.ProductoTalla AS PT
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        WHERE (PT.IdProductoTalla = @inIdProductoTalla)
            AND (P.FlagActivo = @true);

        IF (@existencias IS NULL)
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o fue eliminado
            RETURN;
        END;

        -- GP007 restricción 1 y flujo alterno 2: talla agotada
        IF (@existencias <= @sinExistencias)
        BEGIN
            SET @outResultCode = 50047; -- talla agotada
            RETURN;
        END;

        BEGIN TRANSACTION tAgregarAlCarrito;

            -- bloquea la línea del carrito: dos clics seguidos no la duplican
            SELECT @enCarrito = CD.Cantidad
            FROM dbo.CarritoDetalle AS CD WITH (UPDLOCK, HOLDLOCK)
            WHERE (CD.IdUsuario = @inIdUsuario)
                AND (CD.IdProductoTalla = @inIdProductoTalla);

            SET @enCarrito = ISNULL(@enCarrito, 0);

            -- GP007 restricción 2: lo del carrito + lo nuevo no supera las existencias
            IF ((@enCarrito + @inCantidad) > @existencias)
            BEGIN
                ROLLBACK TRANSACTION;
                SET @outResultCode = 50048; -- supera las existencias

                -- datos para el mensaje: "Solo hay N disponibles y ya tiene M en el carrito"
                SELECT @existencias AS Existencias
                    , @enCarrito AS EnCarrito;
                RETURN;
            END;

            IF (@enCarrito > 0)
            BEGIN
                UPDATE dbo.CarritoDetalle
                SET Cantidad = Cantidad + @inCantidad
                    , FechaAgregado = GETDATE()
                WHERE (IdUsuario = @inIdUsuario)
                    AND (IdProductoTalla = @inIdProductoTalla);
            END
            ELSE
            BEGIN
                INSERT INTO dbo.CarritoDetalle (
                    IdUsuario
                    , IdProductoTalla
                    , Cantidad
                    , FechaAgregado
                )
                VALUES (
                    @inIdUsuario
                    , @inIdProductoTalla
                    , @inCantidad
                    , GETDATE()
                );
            END;

        COMMIT TRANSACTION tAgregarAlCarrito;

        -- primer resultado: indicador de productos del carrito (GP007 paso 2.3)
        SELECT ISNULL(SUM(CD.Cantidad), 0) AS CantidadArticulos
        FROM dbo.CarritoDetalle AS CD
        WHERE (CD.IdUsuario = @inIdUsuario);

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
