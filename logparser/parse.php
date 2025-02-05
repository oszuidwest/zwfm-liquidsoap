<?php

// Composer autoloader voor DeviceDetector
require __DIR__ . '/vendor/autoload.php';

use DeviceDetector\DeviceDetector;
use DeviceDetector\Parser\Client\Browser;

// Lees de ignorelist.txt in
$ignoreListFile = __DIR__ . '/ignorelist.txt';  // Pad naar ignorelist.txt
$ignoreList = [];

if (file_exists($ignoreListFile)) {
    $lines = file($ignoreListFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        // Indien er een '#' in de regel staat, splitsen we daarop om het IP te isoleren
        if (strpos($line, '#') !== false) {
            $parts = explode('#', $line, 2);
            $line = trim($parts[0]); // Neem alleen het deel vóór '#'
        }
        // Het restant is (hopelijk) een IP; als het niet leeg is, voegen we het toe aan de lijst
        $ipCandidate = trim($line);
        if (!empty($ipCandidate)) {
            $ignoreList[] = $ipCandidate;
        }
    }
}

// Maak (of open) de SQLite database
$dbFile = __DIR__ . '/sessions.db';
$pdo = new PDO('sqlite:' . $dbFile);
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

// Maak de tabel (als deze nog niet bestaat)
$createTableQuery = "
    CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date DATETIME,
        ip TEXT,
        agent TEXT,
        mount TEXT,
        duration INTEGER,
        listener_hash TEXT,
        device_type TEXT
    )
";
$pdo->exec($createTableQuery);

// Pad naar de logfile
$logfile = __DIR__ . '/logfile.log';
$handle = fopen($logfile, 'r');
if (!$handle) {
    die("Kan het logbestand niet openen: $logfile");
}

// Voorbereiden van INSERT-statement
$insertStmt = $pdo->prepare("
    INSERT INTO sessions (date, ip, agent, mount, duration, listener_hash, device_type)
    VALUES (:date, :ip, :agent, :mount, :duration, :listener_hash, :device_type)
");

// Regex om de logregel te parsen
$pattern = '/^(?<ip>\S+)\s+\S+\s+\S+\s+\[(?<timestamp>[^\]]+)\]\s+"(?<request_line>[^"]+)"\s+(?<status>\d+)\s+(?<bytes>\d+)\s+"(?<referrer>[^"]+)"\s+"(?<agent>[^"]+)"\s+(?<duration>\d+)/';

// Verwerken van elke regel in de logfile
while (($line = fgets($handle)) !== false) {
    if (preg_match($pattern, $line, $matches)) {
        $ip       = $matches['ip'];
        $duration = (int)$matches['duration'];

        // Controleer of IP in de ignoreList staat
        if (in_array($ip, $ignoreList)) {
            // Als dit IP in de ignorelist zit, skip deze regel
            continue;
        }

        // Filter op duration > 10
        if ($duration > 10) {
            // Timestamp parsen
            $dateString = $matches['timestamp'];
            $dateObj = DateTime::createFromFormat('d/M/Y:H:i:s O', $dateString);
            if (!$dateObj) {
                continue;
            }
            $isoDate = $dateObj->format('Y-m-d H:i:s');

            // User-Agent, mount, hash
            $agent = $matches['agent'];
            $requestParts = explode(' ', $matches['request_line']);
            $mount = isset($requestParts[1]) ? $requestParts[1] : '';
            $listenerHash = md5($ip . $agent);

            // DeviceDetector gebruiken
            $dd = new DeviceDetector($agent);
            $dd->parse();

            $deviceType = 'unknown';
            if ($dd->isBot()) {
                // Eventueel device_type = 'bot'
                $deviceType = 'bot';
            } else {
                $deviceName = $dd->getDeviceName();
                if (!empty($deviceName)) {
                    $deviceType = $deviceName;
                }
            }

            // Insert
            $insertStmt->execute([
                ':date'         => $isoDate,
                ':ip'           => $ip,
                ':agent'        => $agent,
                ':mount'        => $mount,
                ':duration'     => $duration,
                ':listener_hash'=> $listenerHash,
                ':device_type'  => $deviceType
            ]);
        }
    }
}

fclose($handle);

echo "Klaar met parsen en opslaan.\n";
