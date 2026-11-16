CREATE OR ALTER PROCEDURE dbo.spListarCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdMetodoEntrega INT -- método de entrega elegido (NULL = aún no elige)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP008 Visualizar carrito y GP020 Calcular costo del pedido.
Se llama al ver el carrito, después de cada cambio (GP009) y al elegir el
método de entrega (GP012 paso 6.2), así el total siempre está al día
(GP020 restricción 3). Usa el precio vigente del producto (GP020 paso 2.1).

Un producto "No disponible" (eliminado, agotado o con menos existencias que
la cantidad del carrito) se marca y NO entra en el total (GP008 flujo alterno 2,
GP020 flujo alterno 2).
Si el método tiene envío y CostoEnvio es NULL, el total es solo de productos y
EnvioACoordinar = 1: "Envío a coordinar con la administradora" (GP020).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarCarrito
        @inIdUsuario = 2
        , @inIdMetodoEntrega = 4
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @sinExistencias INT = 0;

        -- variables de uso general
        DECLARE @costoEnvio MONEY
            , @requiereDireccion BIT
            , @envioACoordinar BIT
            , @subtotalProductos MONEY;

        -- líneas del carrito con su disponibilidad actual
        DECLARE @lineas TABLE (
            IdCarritoDetalle INT NOT NULL PRIMARY KEY
            , IdProductoTalla INT NOT NULL
            , IdProducto INT NOT NULL
            , Nombre NVARCHAR(100) NOT NULL
            , RutaImagen VARCHAR(260) NULL
            , Talla NVARCHAR(16) NOT NULL
            , Cantidad INT NOT NULL
            , PrecioUnitario MONEY NOT NULL
            , Existencias INT NOT NULL
            , Disponible BIT NOT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @envioACoordinar = @false;

        -- validaciones
        IF (@inIdMetodoEntrega IS NOT NULL)
        BEGIN
            SELECT @costoEnvio = ME.CostoEnvio
                , @requiereDireccion = ME.FlagRequiereDireccion
            FROM dbo.MetodoEntrega AS ME
            WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega);

            IF (@requiereDireccion IS NULL)
            BEGIN
                SET @outResultCode = 50051; -- método de entrega no válido
                RETURN;
            END;

            SET @envioACoordinar = CASE
                    WHEN (@requiereDireccion = @true) AND (@costoEnvio IS NULL) THEN @true
                    ELSE @false
                END;
        END;

        INSERT INTO @lineas (
            IdCarritoDetalle
            , IdProductoTalla
            , IdProducto
            , Nombre
            , RutaImagen
            , Talla
            , Cantidad
            , PrecioUnitario
            , Existencias
            , Disponible
        )
        SELECT CD.IdCarritoDetalle
            , CD.IdProductoTalla
            , P.IdProducto
            , P.Nombre
            , P.RutaImagen
            , T.Nombre
            , CD.Cantidad
            , P.Precio
            , CASE
                WHEN (P.FlagActivo = @true) THEN PT.Cantidad
                ELSE @sinExistencias
              END
            , CASE
                WHEN (P.FlagActivo = @true) AND (PT.Cantidad >= CD.Cantidad) THEN @true
                ELSE @false
              END
        FROM dbo.CarritoDetalle AS CD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = CD.IdProductoTalla)
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        INNER JOIN dbo.Talla AS T
            ON (T.IdTalla = PT.IdTalla)
        WHERE (CD.IdUsuario = @inIdUsuario);

        SELECT @subtotalProductos = ISNULL(SUM(L.PrecioUnitario * L.Cantidad), 0)
        FROM @lineas AS L
        WHERE (L.Disponible = @true);

        -- primer resultado: líneas del carrito (GP008 restricción 1).
        -- Vacío = "Su carrito está vacío"
        SELECT L.IdCarritoDetalle
            , L.IdProductoTalla
            , L.IdProducto
            , L.Nombre
            , L.RutaImagen
            , L.Talla
            , L.Cantidad
            , L.PrecioUnitario
            , (L.PrecioUnitario * L.Cantidad) AS Subtotal
            , L.Existencias
            , L.Disponible
        FROM @lineas AS L
        ORDER BY L.Disponible DESC -- los no disponibles al final
            , L.IdCarritoDetalle;

        -- segundo resultado: desglose del costo (GP020 paso 2.4)
        SELECT @subtotalProductos AS SubtotalProductos
            , @costoEnvio AS CostoEnvio
            , @envioACoordinar AS EnvioACoordinar
            , (@subtotalProductos + ISNULL(@costoEnvio, 0)) AS Total
            , ISNULL((SELECT SUM(L.Cantidad) FROM @lineas AS L), 0) AS CantidadArticulos
            , CASE
                WHEN EXISTS (SELECT 1 FROM @lineas AS L WHERE (L.Disponible = @false)) THEN @true
                ELSE @false
              END AS HayNoDisponibles;

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
