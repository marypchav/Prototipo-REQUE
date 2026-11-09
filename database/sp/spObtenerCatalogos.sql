CREATE OR ALTER PROCEDURE dbo.spObtenerCatalogos
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Devuelve todos los catálogos que el sitio necesita para llenar listas
desplegables (formularios de producto, dirección, pago y entrega).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerCatalogos
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: categorías
        SELECT C.IdCategoria
            , C.Nombre
        FROM dbo.Categoria AS C
        ORDER BY C.Nombre;

        -- segundo resultado: tallas, en su orden lógico (XS, S, M...)
        SELECT T.IdTalla
            , T.Nombre
        FROM dbo.Talla AS T
        ORDER BY T.Orden;

        -- tercer resultado: provincias
        SELECT PR.IdProvincia
            , PR.Nombre
        FROM dbo.Provincia AS PR
        ORDER BY PR.IdProvincia;

        -- cuarto resultado: métodos de pago
        SELECT MP.IdMetodoPago
            , MP.Nombre
            , MP.FlagRequiereComprobante
            , MP.FlagSoloRetiro
        FROM dbo.MetodoPago AS MP
        ORDER BY MP.IdMetodoPago;

        -- quinto resultado: métodos de entrega
        SELECT ME.IdMetodoEntrega
            , ME.Nombre
            , ME.FlagRequiereDireccion
            , ME.CostoEnvio
        FROM dbo.MetodoEntrega AS ME
        ORDER BY ME.IdMetodoEntrega;

        -- sexto resultado: estados de pedido
        SELECT EP.IdEstadoPedido
            , EP.Nombre
            , EP.FlagRequiereMotivo
        FROM dbo.EstadoPedido AS EP
        ORDER BY EP.IdEstadoPedido;

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
