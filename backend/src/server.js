/*
Punto de entrada: verifica la conexión a SQL Server y levanta el servidor.
    npm run dev   -> modo desarrollo (se reinicia solo al guardar)
    npm start     -> modo normal
*/
const os = require('os');
const http = require('http');
const config = require('./env');
const app = require('./app');
const { obtenerPool } = require('./conexion');
const { iniciarTiempoReal } = require('./tiempoReal');
const { iniciarNotificaciones } = require('./notificaciones');

// direcciones IPv4 de esta computadora (red local, Radmin VPN, etc.)
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

  // el puerto ya lo usa otro programa: casi siempre otro "npm run dev" abierto
  servidor.on('error', (error) => {
    if (error.code === 'EADDRINUSE') {
      console.error(`El puerto ${config.puerto} ya está en uso: hay otro servidor corriendo.`);
      console.error('Ciérrelo con Ctrl + C en la otra terminal, o en PowerShell:');
      console.error(
        `  Get-NetTCPConnection -LocalPort ${config.puerto} -State Listen | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }`
      );
      console.error('Después escriba rs aquí para volver a intentar.');
    } else {
      console.error('No se pudo iniciar el servidor:', error.message);
    }
    process.exit(1);
  });

  // sin indicar host, escucha en todas las redes de la computadora,
  // así que también responde por la IP de Radmin VPN
  servidor.listen(config.puerto, () => {
    console.log(`Servidor listo en http://localhost:${config.puerto}`);
    console.log('Desde otras computadoras:');
    for (const { nombre, ip } of direccionesDeRed()) {
      // Radmin VPN usa direcciones 26.x.x.x
      const marca = ip.startsWith('26.') ? '   <- Radmin VPN' : '';
      console.log(`  ${nombre}: http://${ip}:${config.puerto}${marca}`);
    }
    iniciarNotificaciones(); // GP019: correos de cambio de estado
  });
}

iniciar();
