/*
Pool de conexiones a SQL Server.
Se crea una sola vez y todas las peticiones lo comparten.
*/
const sql = require('mssql');
const config = require('./env');

let poolPromesa = null;

function obtenerPool() {
  if (!poolPromesa) {
    poolPromesa = new sql.ConnectionPool(config.db)
      .connect()
      .catch((error) => {
        poolPromesa = null; // permite reintentar en la siguiente petición
        throw error;
      });
  }
  return poolPromesa;
}

module.exports = { sql, obtenerPool };
