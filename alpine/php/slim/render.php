<?php

// Config rendering for php-slim, which has no bash and no envsubst. Run with php -n so no
// ini file (possibly not rendered yet) is read.
//
//   php -n render.php <template> <output>     ${VAR} replaced from the environment; unset
//                                             variables become empty, as with envsubst
//   php -n render.php --append <prefix> <file> append "key = value" for every <prefix>.<key>
//                                             environment variable, sorted by name

declare(strict_types=1);

if (($argv[1] ?? '') === '--append') {
    [, , $prefix, $file] = $argv;
    // getenv() without arguments turns the dots in names into underscores, so read the raw
    // environment block instead
    $overrides = [];
    foreach (explode("\0", (string) file_get_contents('/proc/self/environ')) as $entry) {
        [$name, $value] = array_pad(explode('=', $entry, 2), 2, '');
        if (str_starts_with($name, $prefix . '.') && strlen($name) > strlen($prefix) + 1) {
            $overrides[substr($name, strlen($prefix) + 1)] = $value;
        }
    }
    if ($overrides === []) {
        exit(0);
    }
    ksort($overrides);
    $lines = sprintf("\n; overrides from %s.* environment variables\n", $prefix);
    foreach ($overrides as $key => $value) {
        $lines .= sprintf("%s = %s\n", $key, $value);
    }
    file_put_contents($file, $lines, FILE_APPEND);
    fwrite(STDERR, sprintf("[entrypoint] INFO: applied %d %s.* override(s) to %s\n", count($overrides), $prefix, $file));
    exit(0);
}

[, $template, $output] = $argv;
$rendered = preg_replace_callback(
    '/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/',
    static fn (array $match): string => (string) getenv($match[1]),
    (string) file_get_contents($template),
);
file_put_contents($output, $rendered);
