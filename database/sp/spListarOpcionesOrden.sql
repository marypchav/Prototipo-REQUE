CREATE OR ALTER PROCEDURE dbo.spListarOpcionesOrden
    @inIdUsuario INT -- cliente con sesión iniciada
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP011 Seleccionar método de pago y GP012 Seleccionar método de entrega:
opciones para la pantalla de generar la orden.
La tabla no guarda una "orden en proceso": lo elegido vive en la página
hasta GP014, donde spConfirmarOrden valida todo junto.
Reglas para el frontend (vienen como banderas):
  - FlagRequiereDireccion = 1: pedir una dirección (GP012 restricción 2).
  - FlagSoloRetiro = 1 en el pago: deshabilitado si la entrega requiere
    dirección, con el texto "Disponible solo para retiro en el taller" (GP011).
  - FlagRequiereComprobante = 1: habilitar "Adjuntar comprobante" (GP013).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarOpcionesOrden
        @inIdUsuario = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: métodos de entrega (GP012 restricción 1)
        SELECT ME.IdMetodoEntrega
            , ME.Nombre
            , ME.FlagRequiereDireccion
            , ME.CostoEnvio -- NULL = envío a coordinar (GP020)
        FROM dbo.MetodoEntrega AS ME
        ORDER BY ME.IdMetodoEntrega;

        -- segundo resultado: métodos de pago (GP011)
        SELECT MP.IdMetodoPago
            , MP.Nombre
            , MP.FlagRequiereComprobante
            , MP.FlagSoloRetiro
        FROM dbo.MetodoPago AS MP
        ORDER BY MP.IdMetodoPago;

        -- tercer resultado: direcciones del cliente (vacío = GP012 flujo alterno:
        -- ir a agregar dirección)
        SELECT D.IdDireccion
            , PR.Nombre AS Provincia
            , D.Canton
            , D.Distrito
            , D.OtrasSenas
        FROM dbo.Direccion AS D
        INNER JOIN dbo.Provincia AS PR
            ON (PR.IdProvincia = D.IdProvincia)
        WHERE (D.IdUsuario = @inIdUsuario)
            AND (D.FlagActivo = @true)
        ORDER BY D.FechaCreacion DESC
            , D.IdDireccion DESC;

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
