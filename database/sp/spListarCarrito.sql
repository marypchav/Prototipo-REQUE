CREATE OR ALTER PROCEDURE dbo.spListarCarrito
    @inIdUsuario INT -- cliente dueño del carrito
    , @inIdMetodoEntrega INT -- método de entrega elegido (NULL = aún no elige)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP008 Visualizar carrito y GP020 Calcular costo del pedido.
Se llama al abrir el carrito, después de cada cambio (GP009) y al elegir
el método de entrega (GP012), así el total siempre está recalculado.

Devuelve dos resultados:
    1. líneas del carrito; Disponible = 0 si el producto se eliminó o ya no
       hay existencias suficientes (GP008 restricción 3)
    2. resumen: subtotal (solo líneas disponibles), envío y total

Costo = suma(precio unitario x cantidad) + envío (GP020 restricción 1).
CostoEnvio NULL con EnvioACoordinar = 1 -> "Envío a coordinar con la
administradora" (GP020 flujo alternativo).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarCarrito
        @inIdUsuario = 2
        , @inIdMetodoEntrega = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @costoEnvio MONEY
            , @envioACoordinar BIT;

        -- líneas del carrito ya calculadas
        DECLARE @lineas TABLE (
            IdCarritoDetalle INT NOT NULL
            , IdProductoTalla INT NOT NULL
            , IdProducto INT NOT NULL
            , NombreProducto NVARCHAR(100) NOT NULL
            , RutaImagen VARCHAR(260) NULL
            , Talla NVARCHAR(16) NOT NULL
            , Cantidad INT NOT NULL
            , PrecioUnitario MONEY NOT NULL
            , Subtotal MONEY NOT NULL
            , Existencias INT NOT NULL
            , Disponible BIT NOT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @costoEnvio = NULL;
        SET @envioACoordinar = @false;

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

        IF (@inIdMetodoEntrega IS NOT NULL)
            AND NOT EXISTS (
                SELECT 1
                FROM dbo.MetodoEntrega AS ME
                WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega)
            )
        BEGIN
            SET @outResultCode = 50020; -- método de entrega no existe
            RETURN;
        END;

        -- preprocesamiento
        SELECT @costoEnvio = ME.CostoEnvio
            , @envioACoordinar = CASE
                WHEN (ME.CostoEnvio IS NULL) THEN @true
                ELSE @false
              END
        FROM dbo.MetodoEntrega AS ME
        WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega);

        -- se usa el precio vigente (GP020 paso 2.1)
        INSERT INTO @lineas (
            IdCarritoDetalle
            , IdProductoTalla
            , IdProducto
            , NombreProducto
            , RutaImagen
            , Talla
            , Cantidad
            , PrecioUnitario
            , Subtotal
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
            , P.Precio * CD.Cantidad
            , PT.Cantidad
            , CASE
                WHEN (P.FlagActivo = @true)
                    AND (PT.Cantidad >= CD.Cantidad) THEN @true
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

        -- primer resultado: líneas
        SELECT L.IdCarritoDetalle
            , L.IdProductoTalla
            , L.IdProducto
            , L.NombreProducto
            , L.RutaImagen
            , L.Talla
            , L.Cantidad
            , L.PrecioUnitario
            , L.Subtotal
            , L.Existencias
            , L.Disponible
        FROM @lineas AS L
        ORDER BY L.IdCarritoDetalle;

        -- segundo resultado: resumen. Los no disponibles no suman (GP008 alterno)
        SELECT ISNULL(SUM(CASE WHEN (L.Disponible = @true) THEN L.Subtotal ELSE 0 END), 0) AS SubtotalProductos
            , @costoEnvio AS CostoEnvio
            , @envioACoordinar AS EnvioACoordinar
            , ISNULL(SUM(CASE WHEN (L.Disponible = @true) THEN L.Subtotal ELSE 0 END), 0)
                + ISNULL(@costoEnvio, 0) AS Total
            , COUNT(1) AS CantidadLineas
            , ISNULL(SUM(CASE WHEN (L.Disponible = @false) THEN 1 ELSE 0 END), 0) AS CantidadNoDisponibles
        FROM @lineas AS L;

    END TRY
    BEGIN CATCH

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
