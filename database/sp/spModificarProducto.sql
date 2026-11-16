CREATE OR ALTER PROCEDURE dbo.spModificarProducto
    @inIdProducto INT -- producto que se modifica
    , @inNombre NVARCHAR(100) -- nombre del producto
    , @inDescripcion NVARCHAR(500) -- descripción (opcional)
    , @inIdCategoria INT -- categoría del producto
    , @inPrecio DECIMAL(12, 2) -- precio en colones
    , @inTallasJson NVARCHAR(MAX) -- existencias por talla: [{"idTalla":2,"cantidad":5}]
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI005 Modificar producto. Recibe el formulario completo: datos del producto
y la cantidad de cada talla. Una talla que ya tenía el producto y no viene en
el JSON queda en 0 (no se borra, porque los pedidos la pueden referenciar).
GI005 restricción 2 (ACID): todo va en una transacción y la fila del producto
se bloquea, así una compra simultánea espera a que termine el cambio.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spModificarProducto
        @inIdProducto = 1
        , @inNombre = N'Blusa de lino'
        , @inDescripcion = N'Blusa manga corta, lino 100 %'
        , @inIdCategoria = 1
        , @inPrecio = 11900
        , @inTallasJson = N'[{"idTalla":2,"cantidad":2},{"idTalla":3,"cantidad":0}]'
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
        DECLARE @nombre NVARCHAR(100)
            , @descripcion NVARCHAR(500)
            , @tallasJson NVARCHAR(MAX);

        -- existencias por talla que llegan en el JSON
        DECLARE @tallas TABLE (
            IdTalla INT NULL
            , CantidadTexto NVARCHAR(50) NULL
            , Cantidad INT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @nombre = NULLIF(LTRIM(RTRIM(@inNombre)), N'');
        SET @descripcion = ISNULL(LTRIM(RTRIM(@inDescripcion)), N'');
        SET @tallasJson = NULLIF(LTRIM(RTRIM(@inTallasJson)), N'');

        -- validaciones (GI005 restricción 1 y criterio de aceptación 2)
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

        IF (@nombre IS NULL)
            OR (@inIdCategoria IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        IF (@inPrecio IS NULL)
            OR (@inPrecio <= 0)
        BEGIN
            SET @outResultCode = 50022; -- precio inválido
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categoria AS C
            WHERE (C.IdCategoria = @inIdCategoria)
        )
        BEGIN
            SET @outResultCode = 50023; -- la categoría no existe
            RETURN;
        END;

        IF (@tallasJson IS NULL)
            OR (ISNULL(ISJSON(@tallasJson), 0) = 0)
            OR (LEFT(@tallasJson, 1) <> '[')
        BEGIN
            SET @outResultCode = 50025; -- lista de tallas inválida
            RETURN;
        END;

        -- preprocesamiento: separa las tallas del JSON. La cantidad se lee como
        -- texto para poder rechazar negativos, decimales y letras
        INSERT INTO @tallas (
            IdTalla
            , CantidadTexto
        )
        SELECT TRY_CAST(J.IdTalla AS INT)
            , LTRIM(RTRIM(J.Cantidad))
        FROM OPENJSON(@tallasJson)
        WITH (
            IdTalla NVARCHAR(50) '$.idTalla'
            , Cantidad NVARCHAR(50) '$.cantidad'
        ) AS J;

        UPDATE @tallas
        SET Cantidad = CASE
                WHEN (CantidadTexto NOT LIKE N'%[^0-9]%')
                    AND (LEN(CantidadTexto) BETWEEN 1 AND 9)
                    THEN TRY_CAST(CantidadTexto AS INT)
                ELSE NULL
            END;

        -- talla vacía, inexistente o repetida
        IF EXISTS (
            SELECT 1
            FROM @tallas AS TA
            WHERE (TA.IdTalla IS NULL)
                OR NOT EXISTS (
                    SELECT 1
                    FROM dbo.Talla AS T
                    WHERE (T.IdTalla = TA.IdTalla)
                )
        )
            OR EXISTS (
                SELECT TA.IdTalla
                FROM @tallas AS TA
                GROUP BY TA.IdTalla
                HAVING (COUNT(*) > 1)
            )
        BEGIN
            SET @outResultCode = 50025; -- lista de tallas inválida
            RETURN;
        END;

        IF EXISTS (
            SELECT 1
            FROM @tallas AS TA
            WHERE (TA.Cantidad IS NULL)
        )
        BEGIN
            SET @outResultCode = 50024; -- cantidad inválida
            RETURN;
        END;

        BEGIN TRANSACTION tModificarProducto;

            -- bloquea el producto y vuelve a revisar: pudo eliminarse mientras tanto
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.Producto AS P WITH (UPDLOCK, HOLDLOCK)
                WHERE (P.IdProducto = @inIdProducto)
                    AND (P.FlagActivo = @true)
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @outResultCode = 50011; -- producto no existe o fue eliminado
                RETURN;
            END;

            UPDATE dbo.Producto
            SET Nombre = @nombre
                , Descripcion = @descripcion
                , IdCategoria = @inIdCategoria
                , Precio = @inPrecio
            WHERE (IdProducto = @inIdProducto);

            -- tallas que ya tenía: toman la cantidad nueva, o 0 si no vienen
            UPDATE PT
            SET PT.Cantidad = ISNULL(TA.Cantidad, @sinExistencias)
            FROM dbo.ProductoTalla AS PT
            LEFT JOIN @tallas AS TA
                ON (TA.IdTalla = PT.IdTalla)
            WHERE (PT.IdProducto = @inIdProducto);

            -- tallas nuevas para este producto (las que vienen en 0 no se agregan)
            INSERT INTO dbo.ProductoTalla (
                IdProducto
                , IdTalla
                , Cantidad
            )
            SELECT @inIdProducto
                , TA.IdTalla
                , TA.Cantidad
            FROM @tallas AS TA
            WHERE (TA.Cantidad > @sinExistencias)
                AND NOT EXISTS (
                    SELECT 1
                    FROM dbo.ProductoTalla AS PT
                    WHERE (PT.IdProducto = @inIdProducto)
                        AND (PT.IdTalla = TA.IdTalla)
                );

        COMMIT TRANSACTION tModificarProducto;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deja el producto como estaba
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
