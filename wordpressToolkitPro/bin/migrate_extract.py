#!/usr/bin/env python3
"""Safely unpack a WordPress migration archive and locate its site files + SQL dump."""
import os, sys, tarfile, zipfile, shutil, gzip
from pathlib import Path, PurePosixPath

archive, destination = sys.argv[1:3]
dest = Path(destination).resolve()
dest.mkdir(parents=True, exist_ok=True)
MAX_FILES = 300000
MAX_TOTAL_BYTES = 20 * 1024 * 1024 * 1024
MAX_SQL_BYTES = 20 * 1024 * 1024 * 1024
total_bytes = 0

def safe_target(name):
    p = PurePosixPath(name.replace('\\', '/'))
    if p.is_absolute() or any(part in ('..', '') for part in p.parts):
        raise ValueError('Unsafe path in archive: ' + name)
    target = (dest / Path(*p.parts)).resolve()
    if dest not in target.parents and target != dest:
        raise ValueError('Archive path escapes staging directory')
    return target

count = 0
if zipfile.is_zipfile(archive):
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if info.is_dir(): continue
            count += 1
            total_bytes += info.file_size
            if total_bytes > MAX_TOTAL_BYTES: raise ValueError('Archive expands beyond the 20 GB safety limit')
            if shutil.disk_usage(dest).free < info.file_size + (256 * 1024 * 1024): raise ValueError('Not enough free disk space to safely extract this archive (keep at least 256 MB free)')
            if count > MAX_FILES: raise ValueError('Archive contains too many files')
            target = safe_target(info.filename)
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, open(target, 'wb') as out: shutil.copyfileobj(src, out)
elif tarfile.is_tarfile(archive):
    with tarfile.open(archive, 'r:*') as t:
        for member in t.getmembers():
            if member.isdir(): continue
            if not member.isfile(): continue  # never restore links/devices/FIFOs
            count += 1
            total_bytes += member.size
            if total_bytes > MAX_TOTAL_BYTES: raise ValueError('Archive expands beyond the 20 GB safety limit')
            if shutil.disk_usage(dest).free < member.size + (256 * 1024 * 1024): raise ValueError('Not enough free disk space to safely extract this archive (keep at least 256 MB free)')
            if count > MAX_FILES: raise ValueError('Archive contains too many files')
            target = safe_target(member.name)
            target.parent.mkdir(parents=True, exist_ok=True)
            src = t.extractfile(member)
            if src:
                with src, open(target, 'wb') as out: shutil.copyfileobj(src, out)
else:
    raise ValueError('Unsupported archive. Upload ZIP, TAR, TAR.GZ or TGZ.')

configs = list(dest.rglob('wp-config.php'))
if not configs: raise ValueError('No wp-config.php found. Upload a WordPress site backup, not a full account backup without extracted website files.')
if len(configs) > 1: raise ValueError('More than one WordPress installation found. Create a backup containing only the website you want to migrate.')
wp_root = configs[0].parent
# Find a SQL dump in the archive. Prefer the closest SQL file, then the largest valid dump.
sqls = [p for p in dest.rglob('*') if p.is_file() and (p.name.lower().endswith('.sql') or p.name.lower().endswith('.sql.gz'))]
if not sqls: raise ValueError('No .sql or .sql.gz database dump found in the archive.')
# Dumps that sit inside the website folder are usually stray leftovers (plugin exports). Prefer dumps outside it.
outside = [p for p in sqls if wp_root not in p.parents]
if outside: sqls = outside
# DirectAdmin account backups can contain several database dumps. Match the
# database name in wp-config.php when the conventional define() is present.
config_text = (wp_root / 'wp-config.php').read_text(errors='ignore')
import re
match = re.search(r"define\s*\(\s*['\"]DB_NAME['\"]\s*,\s*['\"]([^'\"]+)['\"]", config_text)
source_db = match.group(1) if match else ''
matching = [p for p in sqls if source_db and p.name.lower() in (source_db.lower() + '.sql', source_db.lower() + '.sql.gz')]
if matching:
    sql = matching[0]
else:
    if len(sqls) > 1:
        raise ValueError('Multiple SQL dumps found but none matches DB_NAME in wp-config.php. Upload a single-site backup or ensure the database dump filename matches the WordPress database name.')
    sql = sqls[0]
# Normalize compressed SQL to a plain dump in staging.
if sql.name.lower().endswith('.sql.gz'):
    plain = dest / 'wpt-migration-database.sql'
    expanded = 0
    try:
        with gzip.open(sql, 'rb') as src, open(plain, 'wb') as out:
            while True:
                chunk = src.read(1024 * 1024)
                if not chunk:
                    break
                expanded += len(chunk)
                if expanded > MAX_SQL_BYTES:
                    raise ValueError('Compressed SQL dump expands beyond the 20 GB safety limit')
                if shutil.disk_usage(dest).free < len(chunk) + (256 * 1024 * 1024):
                    raise ValueError('Not enough free disk space to decompress the SQL dump (keep at least 256 MB free)')
                out.write(chunk)
    except Exception:
        try: plain.unlink()
        except OSError: pass
        raise
    sql = plain
print(str(wp_root))
print(str(sql))
