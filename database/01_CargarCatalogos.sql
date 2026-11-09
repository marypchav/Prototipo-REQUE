/*
Carga los catálogos de BDCapanni y la cuenta de la administradora.
Se ejecuta una sola vez, después de 00_CrearTablas.sql.
*/
USE BDCapanni;
GO

SET NOCOUNT ON;

BEGIN TRY

    BEGIN TRANSACTION tCargarCatalogos;

        -- tipos de operación de la bitácora
        INSERT INTO dbo.TipoOperacion (IdTipoOperacion, Nombre)
        VALUES (1, N'Registrar cliente')
            , (2, N'Agregar producto')
            , (3, N'Modificar producto')
            , (4, N'Eliminar producto')
            , (5, N'Actualizar disponibilidad')
            , (6, N'Subir foto de producto')
            , (7, N'Agregar dirección')
            , (8, N'Modificar dirección')
            , (9, N'Eliminar dirección')
            , (10, N'Confirmar orden de compra')
            , (11, N'Cambiar estado de pedido');

        INSERT INTO dbo.Provincia (IdProvincia, Nombre)
        VALUES (1, N'San José')
            , (2, N'Alajuela')
            , (3, N'Cartago')
            , (4, N'Heredia')
            , (5, N'Guanacaste')
            , (6, N'Puntarenas')
            , (7, N'Limón');

        -- AJUSTAR con las categorías reales que maneja Confecciones Capanni
        INSERT INTO dbo.Categoria (IdCategoria, Nombre)
        VALUES (1, N'Blusas')
            , (2, N'Vestidos')
            , (3, N'Pantalones')
            , (4, N'Faldas')
            , (5, N'Accesorios');

        -- AJUSTAR con las tallas reales
        INSERT INTO dbo.Talla (IdTalla, Nombre, Orden)
        VALUES (1, N'XS', 1)
            , (2, N'S', 2)
            , (3, N'M', 3)
            , (4, N'L', 4)
            , (5, N'XL', 5)
            , (6, N'Única', 6);

        -- GP011: efectivo solo si se retira en el taller
        INSERT INTO dbo.MetodoPago (IdMetodoPago, Nombre, FlagRequiereComprobante, FlagSoloRetiro)
        VALUES (1, N'SINPE Móvil', 1, 0)
            , (2, N'Efectivo', 0, 1);

        -- GP012. CostoEnvio NULL = "Envío a coordinar con la administradora" (GP020).
        -- Si la clienta define tarifas fijas, se ponen aquí
        INSERT INTO dbo.MetodoEntrega (IdMetodoEntrega, Nombre, FlagRequiereDireccion, CostoEnvio)
        VALUES (1, N'Correos de Costa Rica', 1, NULL)
            , (2, N'Encomienda', 1, NULL)
            , (3, N'Plataforma de transporte', 1, NULL)
            , (4, N'Retiro en el taller', 0, 0);

        -- GP017
        INSERT INTO dbo.EstadoPedido (IdEstadoPedido, Nombre, FlagRequiereMotivo, FlagDevuelveInventario)
        VALUES (1, N'Pendiente de confirmación', 0, 0)
            , (2, N'Confirmado', 0, 0)
            , (3, N'En preparación', 0, 0)
            , (4, N'Enviado', 0, 0)
            , (5, N'Listo para retiro', 0, 0)
            , (6, N'Entregado', 0, 0)
            , (7, N'Rechazado', 1, 1)
            , (8, N'Cancelado', 1, 1);

        -- transiciones válidas (los estados solo avanzan)
        INSERT INTO dbo.TransicionEstadoPedido (IdEstadoActual, IdEstadoNuevo, FlagSoloEnvio, FlagSoloRetiro)
        VALUES (1, 2, 0, 0) -- pendiente -> confirmado (GP016)
            , (1, 7, 0, 0) -- pendiente -> rechazado (GP016 flujo alternativo)
            , (2, 3, 0, 0) -- confirmado -> en preparación
            , (2, 8, 0, 0) -- confirmado -> cancelado
            , (3, 4, 1, 0) -- en preparación -> enviado (solo con envío)
            , (3, 5, 0, 1) -- en preparación -> listo para retiro (solo retiro)
            , (3, 8, 0, 0) -- en preparación -> cancelado
            , (4, 6, 1, 0) -- enviado -> entregado
            , (5, 6, 0, 1); -- listo para retiro -> entregado

        -- cuenta de la administradora (GI001: ya existe en la base de datos).
        -- REEMPLAZAR el hash por uno real generado con bcrypt, por ejemplo:
        --   node -e "console.log(require('bcrypt').hashSync('SuContraseña', 10))"
        INSERT INTO dbo.Usuario (Nombre, Correo, Telefono, PassHash, EsAdministrador)
        VALUES (
            N'Carmen Acuña Padilla'
            , 'admin@capanni.com'
            , '88888888'
            , '$2b$10$REEMPLAZAR_POR_HASH_REAL_GENERADO_CON_BCRYPT'
            , 1
        );

    COMMIT TRANSACTION tCargarCatalogos;

END TRY
BEGIN CATCH

    IF (@@TRANCOUNT > 0)
    BEGIN
        ROLLBACK TRANSACTION;
    END;

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

    SELECT ERROR_MESSAGE() AS Error;

END CATCH;

SET NOCOUNT OFF;
GO
