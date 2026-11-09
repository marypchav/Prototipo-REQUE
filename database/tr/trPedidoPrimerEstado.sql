CREATE OR ALTER TRIGGER dbo.trPedidoPrimerEstado
ON dbo.Pedido
AFTER INSERT
AS
/*
Registra en el historial el primer estado de cada pedido ("Pendiente de
confirmación"), para que el historial del cliente (GP018) muestre desde
cuándo existe el pedido.

Ejemplo:
    INSERT INTO dbo.Pedido (IdUsuario, IdEstadoPedido, IdMetodoPago, IdMetodoEntrega
        , DireccionEntrega, SubtotalProductos, CostoEnvio, Total)
    VALUES (2, 1, 2, 4, NULL, 15000, 0, 15000);
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    -- si el INSERT no insertó filas, no hay nada que registrar
    IF NOT EXISTS (
        SELECT 1
        FROM inserted AS I
    )
    BEGIN
        RETURN;
    END;

    -- una fila por cada pedido insertado. Se trabaja sobre "inserted" completo
    -- porque un solo INSERT puede traer varios pedidos
    INSERT INTO dbo.HistorialEstadoPedido (
        IdPedido
        , IdEstadoPedido
        , IdUsuario
        , Comentario
    )
    SELECT I.IdPedido
        , I.IdEstadoPedido
        , I.IdUsuario -- el cliente que creó la orden
        , N'Orden creada por el cliente'
    FROM inserted AS I;

    SET NOCOUNT OFF;
END;
GO
