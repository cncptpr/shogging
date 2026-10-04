<?php

/**
 * Router script for PHP's built-in development server so Nextcloud works
 * without Apache/nginx, mirroring the URL rewriting Nextcloud's .htaccess
 * normally provides:
 *
 *   /.well-known/(card|c)dav      -> 301 /remote.php/dav/
 *   /remote.php/<svc>/<path>      -> sets SCRIPT_NAME/PATH_INFO, runs remote.php
 *   any other existing .php file  -> run it as-is (status.php, index.php, ...)
 *   anything else                 -> index.php front controller
 *
 * Usage: php -S <addr>:<port> -t <nextcloud-root> dev/nextcloud-router.php
 */

declare(strict_types=1);

$uri = (string)parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

// Same redirects as Nextcloud's .htaccess rules for the RFC 6764 well-known
// URIs (shogg's server info discovery expects this 301 + Location header).
if ($uri === '/.well-known/caldav' || $uri === '/.well-known/carddav') {
    header('Location: /remote.php/dav/', true, 301);
    return true;
}

$root = rtrim((string)($_SERVER['DOCUMENT_ROOT'] ?? ''), '/');

// /remote.php/dav/... (or any other entry point with path info): split the URI
// the way a rewrite-capable web server would, then execute the entry point.
if (preg_match('#^(/[^?]+\.php)(/.*)?$#', $uri, $m) === 1 && is_file($root . $m[1])) {
    $pathInfo = $m[2] ?? '';
    if ($pathInfo === '') {
        return false; // plain request for an existing script
    }
    $_SERVER['SCRIPT_NAME'] = $m[1];
    $_SERVER['SCRIPT_FILENAME'] = $root . $m[1];
    $_SERVER['PHP_SELF'] = $m[1] . $pathInfo;
    $_SERVER['PATH_INFO'] = $pathInfo;
    chdir(dirname($root . $m[1]));
    require $root . $m[1];
    return true;
}

// Existing static file: let the built-in server serve it.
if ($uri !== '/' && is_file($root . $uri)) {
    return false;
}

// Front controller for everything else.
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_SERVER['SCRIPT_FILENAME'] = $root . '/index.php';
$_SERVER['PHP_SELF'] = '/index.php';
chdir($root);
require $root . '/index.php';
return true;
