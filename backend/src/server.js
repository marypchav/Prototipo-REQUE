/*
Punto de entrada: verifica la conexión a SQL Server y levanta el servidor.
*/
const os = require('os');
const http = require('http');
const config = require('./env');
const app = require('./app');
const { obtenerPool } = require('./conexion');
const { iniciarTiempoReal } = require('./tiempoReal');

// direcciones IPv4 de mi compu
function direccionesDeRed() {
  return Object.entries(os.networkInterfaces()).flatMap(([nombre, interfaces]) =>
    (interfaces || [])
      .filter((interfaz) => interfaz.family === 'IPv4' && !interfaz.internal)
      .map((interfaz) => ({ nombre, ip: interfaz.address }))
  );
}

async function iniciar() {
  try {
    await obtenerPool();
    console.log(`Conectado a SQL Server, base ${config.db.database}`);
  } catch (error) {
    console.error('No se pudo conectar a SQL Server:', error.message);
    console.error('Revise el archivo .env y la guía INSTALACION.md.');
    process.exit(1);
  }

  // Express y Socket.IO (CP010) comparten el mismo servidor y el mismo puerto
  const servidor = http.createServer(app);
  iniciarTiempoReal(servidor);

  // sin indicar host, escucha en todas las redes de la computadora, así que también responde por la IP de Hamachi
  servidor.listen(config.puerto, () => {
    console.log(`Servidor listo en http://localhost:${config.puerto}`);
    console.log('Desde otras computadoras:');
    for (const { nombre, ip } of direccionesDeRed()) {
      // Hamachi usa direcciones 25.x.x.x
      const marca = ip.startsWith('25.') ? '   <- Hamachi' : '';
      console.log(`  ${nombre}: http://${ip}:${config.puerto}${marca}`);
    }
  });
}

iniciar();
