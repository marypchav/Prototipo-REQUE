CREATE OR ALTER PROCEDURE dbo.spActualizarExistencias
    @inIdProducto INT -- producto al que se le ajusta la disponibilidad
    , @inTallasJson NVARCHAR(MAX) -- tallas a cambiar: [{"idTalla":2,"cantidad":0}]
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI007 Actualizar disponibilidad del producto. Cambia solo las tallas que
vienen en el JSON; las demás quedan igual. Cantidad 0 = esa talla se agota
(GI007 postcondición 2).
GI007 restricción 2 (ACID): transacción y bloqueo del producto, para que una
compra al mismo tiempo no lea una cantidad a medio cambiar.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarExistencias
        @inIdProducto = 1
        , @inTallasJson = N'[{"idTalla":2,"cantidad":0},{"idTalla":4,"cantidad":3}]'
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
        DECLARE @tallasJson NVARCHAR(MAX);

        -- existencias por talla que llegan en el JSON
        DECLARE @tallas TABLE (
            IdTalla INT NULL
            , CantidadTexto NVARCHAR(50) NULL
            , Cantidad INT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @tallasJson = NULLIF(LTRIM(RTRIM(@inTallasJson)), N'');

        -- validaciones
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

        IF (@tallasJson IS NULL)
            OR (ISNULL(ISJSON(@tallasJson), 0) = 0)
            OR (LEFT(@tallasJson, 1) <> '[')
        BEGIN
            SET @outResultCode = 50025; -- lista de tallas inválida
            RETURN;
        END;

        -- preprocesamiento: separa las tallas del JSON
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

        -- arreglo vacío, talla vacía, inexistente o repetida
        IF NOT EXISTS (SELECT 1 FROM @tallas)
            OR EXISTS (
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

        -- GI007 restricción 1: entero mayor o igual que cero
        IF EXISTS (
            SELECT 1
            FROM @tallas AS TA
            WHERE (TA.Cantidad IS NULL)
        )
        BEGIN
            SET @outResultCode = 50024; -- cantidad inválida
            RETURN;
        END;

        BEGIN TRANSACTION tActualizarExistencias;

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

            -- tallas que el producto ya tiene
            UPDATE PT
            SET PT.Cantidad = TA.Cantidad
            FROM dbo.ProductoTalla AS PT
            INNER JOIN @tallas AS TA
                ON (TA.IdTalla = PT.IdTalla)
            WHERE (PT.IdProducto = @inIdProducto);

            -- tallas nuevas para este producto
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

        COMMIT TRANSACTION tActualizarExistencias;

    END TRY
    BEGIN CATCH

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
