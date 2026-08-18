#!/usr/bin/env python3
"""
scripts/wire-services.py
========================
Automated Post-Sync Service Orchestrator & Cross-Wiring Engine for Taiflix.
Connects Prowlarr, Sonarr, Radarr, Lidarr, Bazarr, qBittorrent, Flaresolverr,
Jellyfin, and Jellyseerr via their REST APIs.
"""

import json
import logging
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("servarr-wire")

# Environment / Secret Configuration
ADMIN_PASSWORD = os.getenv(
    "ADMIN_PASSWORD", "change_me_super_secret_admin_password_123"
)
PROWLARR_API_KEY = os.getenv("PROWLARR_API_KEY", "")
SONARR_API_KEY = os.getenv("SONARR_API_KEY", "")
RADARR_API_KEY = os.getenv("RADARR_API_KEY", "")
LIDARR_API_KEY = os.getenv("LIDARR_API_KEY", "")
BAZARR_API_KEY = os.getenv("BAZARR_API_KEY", "")
JELLYSEERR_API_KEY = os.getenv("JELLYSEERR_API_KEY", "")
JELLYFIN_USERNAME = os.getenv("JELLYFIN_USERNAME", "taian")
JELLYFIN_ADMIN_PASSWORD = os.getenv("JELLYFIN_ADMIN_PASSWORD", ADMIN_PASSWORD)
# JSON list of {name, collectionType, paths} for Jellyfin libraries.
# Defaults match the canonical /media layout documented in README.md.
JELLYFIN_LIBRARIES_JSON = os.getenv(
    "JELLYFIN_LIBRARIES_JSON",
    json.dumps(
        [
            {"name": "Movies", "collectionType": "movies", "paths": ["/media/movies"]},
            {"name": "TV Shows", "collectionType": "tvshows", "paths": ["/media/tv"]},
            {"name": "Music", "collectionType": "music", "paths": ["/media/music"]},
        ]
    ),
)

# Base URLs (Internal Kubernetes DNS names)
URLS = {
    "qbittorrent": os.getenv("QBITTORRENT_URL", "http://qbittorrent:8080"),
    "flaresolverr": os.getenv("FLARESOLVERR_URL", "http://flaresolverr:8191"),
    "prowlarr": os.getenv("PROWLARR_URL", "http://prowlarr:9696"),
    "sonarr": os.getenv("SONARR_URL", "http://sonarr:8989"),
    "radarr": os.getenv("RADARR_URL", "http://radarr:7878"),
    "lidarr": os.getenv("LIDARR_URL", "http://lidarr:8686"),
    "bazarr": os.getenv("BAZARR_URL", "http://bazarr:6767"),
    "jellyfin": os.getenv("JELLYFIN_URL", "http://jellyfin:8096"),
    "jellyseerr": os.getenv("JELLYSEERR_URL", "http://jellyseerr:5055"),
}


def http_request(
    url: str,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    data: Any | None = None,
    timeout: int = 15,
) -> tuple[int, Any, dict[str, str]]:
    """Portable HTTP request helper using standard urllib."""
    req_headers = {"User-Agent": "Taiflix-Wire/1.0", "Accept": "application/json"}
    if headers:
        req_headers.update(headers)

    encoded_data = None
    if data is not None:
        if isinstance(data, (dict, list)):
            encoded_data = json.dumps(data).encode("utf-8")
            req_headers["Content-Type"] = "application/json"
        elif isinstance(data, str):
            encoded_data = data.encode("utf-8")
        elif isinstance(data, bytes):
            encoded_data = data

    req = urllib.request.Request(
        url, data=encoded_data, headers=req_headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            status = response.status
            resp_body = response.read().decode("utf-8", errors="replace")
            resp_headers = dict(response.info())
            try:
                parsed_json = json.loads(resp_body) if resp_body else {}
                return status, parsed_json, resp_headers
            except json.JSONDecodeError:
                return status, resp_body, resp_headers
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        try:
            parsed_err = json.loads(err_body) if err_body else {}
            return e.code, parsed_err, dict(e.headers)
        except json.JSONDecodeError:
            return e.code, err_body, dict(e.headers)
    except Exception as e:
        return 0, str(e), {}


def wait_for_service(
    name: str,
    url: str,
    health_path: str = "/api/v1/system/status",
    api_key: str = "",
    max_retries: int = 24,
    interval: int = 5,
) -> bool:
    """Polls a service until it becomes responsive."""
    logger.info(f"Waiting for {name} ({url})...")
    full_url = f"{url.rstrip('/')}{health_path}"
    headers = {"X-Api-Key": api_key} if api_key else {}

    for attempt in range(1, max_retries + 1):
        status, _, _ = http_request(full_url, headers=headers, timeout=5)
        if status in [200, 201, 204, 401, 403]:
            logger.info(f"Service {name} is READY! (Status: {status})")
            return True
        time.sleep(interval)

    logger.warning(
        f"Service {name} did not become ready after {max_retries * interval}s (continuing best effort)."
    )
    return False


class ServarrWire:
    def __init__(self):
        self.session_cookies: dict[str, str] = {}

    def configure_qbittorrent(self):
        """Authenticates with qBittorrent and configures paths and categories."""
        logger.info("--> Configuring qBittorrent...")
        base_url = URLS["qbittorrent"]

        # 1. Login
        login_url = f"{base_url}/api/v2/auth/login"
        login_data = urllib.parse.urlencode(
            {"username": "admin", "password": ADMIN_PASSWORD}
        )
        status, _, headers = http_request(
            login_url,
            method="POST",
            data=login_data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )

        cookie = headers.get("Set-Cookie", "")
        if "SID=" in cookie:
            sid = cookie.split("SID=")[1].split(";")[0]
            self.session_cookies["qb"] = f"SID={sid}"
            logger.info("Authenticated with qBittorrent.")
        else:
            # Fallback to default admin password if changed
            login_data_default = urllib.parse.urlencode(
                {"username": "admin", "password": "adminadmin"}
            )
            _, _, headers = http_request(
                login_url,
                method="POST",
                data=login_data_default,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            cookie = headers.get("Set-Cookie", "")
            if "SID=" in cookie:
                sid = cookie.split("SID=")[1].split(";")[0]
                self.session_cookies["qb"] = f"SID={sid}"
                logger.info("Authenticated with default qBittorrent credentials.")

        qb_headers = {"Cookie": self.session_cookies.get("qb", "")}

        # 2. Set Preferences (Download paths)
        pref_data = {
            "save_path": "/media/downloads/completed",
            "temp_path": "/media/downloads/incomplete",
            "temp_path_enabled": True,
            "create_subfolder_enabled": False,
            "max_connec": 500,
            "max_uploads": 50,
            "dht": True,
        }
        http_request(
            f"{base_url}/api/v2/app/setPreferences",
            method="POST",
            data=f"json={json.dumps(pref_data)}",
            headers={**qb_headers, "Content-Type": "application/x-www-form-urlencoded"},
        )

        # 3. Create Categories for atomic hardlinks
        categories = {
            "tv-sonarr": "/media/downloads/completed/tv-sonarr",
            "radarr": "/media/downloads/completed/radarr",
            "lidarr": "/media/downloads/completed/lidarr",
            "prowlarr": "/media/downloads/completed/prowlarr",
        }
        for cat_name, save_path in categories.items():
            cat_payload = urllib.parse.urlencode(
                {"category": cat_name, "savePath": save_path}
            )
            http_request(
                f"{base_url}/api/v2/torrents/createCategory",
                method="POST",
                data=cat_payload,
                headers={
                    **qb_headers,
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
        logger.info("qBittorrent categories and paths configured.")

    def configure_prowlarr(self):
        """Wires Prowlarr with Flaresolverr, qBittorrent, Sonarr, Radarr, Lidarr."""
        logger.info("--> Configuring Prowlarr...")
        base_url = URLS["prowlarr"]
        headers = {"X-Api-Key": PROWLARR_API_KEY}

        # 1. Add Flaresolverr Indexer Proxy
        proxy_payload = {
            "name": "Flaresolverr",
            "fields": [
                {"name": "host", "value": URLS["flaresolverr"]},
                {"name": "requestTimeout", "value": 60},
            ],
            "implementationName": "Flaresolverr",
            "implementation": "Flaresolverr",
            "configContract": "FlaresolverrSettings",
            "infoLink": "https://wiki.servarr.com/prowlarr/supported-indexers#flaresolverr",
            "tags": [1],
        }
        http_request(
            f"{base_url}/api/v1/indexerproxy",
            method="POST",
            data=proxy_payload,
            headers=headers,
        )

        # 2. Add Sonarr Application
        sonarr_app = {
            "name": "Sonarr",
            "fields": [
                {"name": "prowlarrUrl", "value": URLS["prowlarr"]},
                {"name": "baseUrl", "value": URLS["sonarr"]},
                {"name": "apiKey", "value": SONARR_API_KEY},
                {
                    "name": "syncCategories",
                    "value": [5000, 5020, 5030, 5040, 5045, 5080],
                },
                {"name": "syncProfile", "value": 1},
            ],
            "implementationName": "Sonarr",
            "implementation": "Sonarr",
            "configContract": "SonarrSettings",
            "syncLevel": "fullSync",
        }
        http_request(
            f"{base_url}/api/v1/applications",
            method="POST",
            data=sonarr_app,
            headers=headers,
        )

        # 3. Add Radarr Application
        radarr_app = {
            "name": "Radarr",
            "fields": [
                {"name": "prowlarrUrl", "value": URLS["prowlarr"]},
                {"name": "baseUrl", "value": URLS["radarr"]},
                {"name": "apiKey", "value": RADARR_API_KEY},
                {
                    "name": "syncCategories",
                    "value": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060],
                },
                {"name": "syncProfile", "value": 1},
            ],
            "implementationName": "Radarr",
            "implementation": "Radarr",
            "configContract": "RadarrSettings",
            "syncLevel": "fullSync",
        }
        http_request(
            f"{base_url}/api/v1/applications",
            method="POST",
            data=radarr_app,
            headers=headers,
        )

        # 4. Add Lidarr Application
        lidarr_app = {
            "name": "Lidarr",
            "fields": [
                {"name": "prowlarrUrl", "value": URLS["prowlarr"]},
                {"name": "baseUrl", "value": URLS["lidarr"]},
                {"name": "apiKey", "value": LIDARR_API_KEY},
                {"name": "syncCategories", "value": [3000, 3010, 3020, 3030, 3040]},
                {"name": "syncProfile", "value": 1},
            ],
            "implementationName": "Lidarr",
            "implementation": "Lidarr",
            "configContract": "LidarrSettings",
            "syncLevel": "fullSync",
        }
        http_request(
            f"{base_url}/api/v1/applications",
            method="POST",
            data=lidarr_app,
            headers=headers,
        )
        logger.info("Prowlarr proxy and applications linked.")

    def configure_arr_service(
        self, name: str, base_url: str, api_key: str, category: str, root_folder: str
    ):
        """Wires an individual *arr service (Sonarr, Radarr, Lidarr)."""
        logger.info(f"--> Configuring {name}...")
        headers = {"X-Api-Key": api_key}
        api_version = "v3" if name in ["Sonarr", "Radarr"] else "v1"

        # 1. Add Root Folder
        root_payload = {"path": root_folder}
        http_request(
            f"{base_url}/api/{api_version}/rootfolder",
            method="POST",
            data=root_payload,
            headers=headers,
        )

        # 2. Add qBittorrent Download Client
        qb_parsed = urllib.parse.urlparse(URLS["qbittorrent"])
        qb_host = qb_parsed.hostname or "qbittorrent"
        qb_port = qb_parsed.port or 8080

        client_payload = {
            "name": "qBittorrent",
            "enable": True,
            "protocol": "torrent",
            "priority": 1,
            "fields": [
                {"name": "host", "value": qb_host},
                {"name": "port", "value": qb_port},
                {"name": "useSsl", "value": False},
                {"name": "username", "value": "admin"},
                {"name": "password", "value": ADMIN_PASSWORD},
                {
                    "name": "tvCategory"
                    if name == "Sonarr"
                    else "movieCategory"
                    if name == "Radarr"
                    else "musicCategory",
                    "value": category,
                },
                {"name": "recentPriority", "value": 0},
                {"name": "olderPriority", "value": 0},
            ],
            "implementationName": "QBittorrent",
            "implementation": "QBittorrent",
            "configContract": "QBittorrentSettings",
        }
        http_request(
            f"{base_url}/api/{api_version}/downloadclient",
            method="POST",
            data=client_payload,
            headers=headers,
        )
        logger.info(
            f"{name} download client and root folder ({root_folder}) configured."
        )

    def configure_arr_jellyfin_notify(
        self, name: str, base_url: str, api_key: str, jellyfin_token: str
    ):
        """Add a 'Connect -> Jellyfin' notification on Sonarr/Radarr so they
        refresh Jellyfin's library when an import happens. Idempotent: skips
        if a connection with the same name already exists."""
        if name not in ("Sonarr", "Radarr"):
            return
        api_version = "v3"
        headers = {"X-Api-Key": api_key}

        # 1. List existing notifications; skip if Jellyfin already wired
        list_status, existing, _ = http_request(
            f"{base_url}/api/{api_version}/notification", headers=headers
        )
        if list_status == 200 and isinstance(existing, list):
            for n in existing:
                if isinstance(n, dict) and n.get("implementation") == "Jellyfin":
                    logger.info(
                        f"{name}: Jellyfin notification already wired, skipping."
                    )
                    return

        # 2. Parse Jellyfin URL -> host/port/ssl
        jf = urllib.parse.urlparse(URLS["jellyfin"])
        jf_host = jf.hostname or "jellyfin"
        jf_port = jf.port or 8080
        jf_ssl = (jf.scheme or "http") == "https"

        payload = {
            "name": "Jellyfin",
            "implementation": "MediaBrowser",
            "configContract": "MediaBrowserSettings",
            # Sonarr/Radarr require these event toggles as top-level fields
            # alongside 'fields' for the schema to validate the notification
            # type (otherwise targetType is null on the server side).
            "onGrab": False,
            "onDownload": True,
            "onUpgrade": True,
            "onRename": True,
            "onHealthIssue": False,
            "onHealthRestored": False,
            "onApplicationUpdate": True,
            "onManualInteractionRequired": False,
            "includeHealthWarnings": False,
            "fields": [
                {"name": "host", "value": jf_host},
                {"name": "port", "value": jf_port},
                {"name": "useSsl", "value": jf_ssl},
                {"name": "urlBase", "value": ""},
                {"name": "apiKey", "value": jellyfin_token},
                {"name": "notify", "value": False},
                {"name": "updateLibrary", "value": True},
            ],
        }
        if name == "Radarr":
            payload.update(
                {
                    "onMovieAdded": True,
                    "onMovieDelete": True,
                    "onMovieFileDelete": True,
                    "onMovieFileDeleteForUpgrade": True,
                }
            )
        elif name == "Sonarr":
            payload.update(
                {
                    "onSeriesAdd": True,
                    "onSeriesDelete": True,
                    "onEpisodeFileDelete": True,
                    "onEpisodeFileDeleteForUpgrade": True,
                    "onImportComplete": True,
                }
            )
        status, body, _ = http_request(
            f"{base_url}/api/{api_version}/notification",
            method="POST",
            data=payload,
            headers=headers,
        )
        if status in (200, 201):
            logger.info(f"{name}: Jellyfin notification wired.")
        else:
            logger.warning(
                f"{name}: Jellyfin notification POST failed status={status} body={body}"
            )

    def configure_bazarr(self):
        """Connects Bazarr to Sonarr and Radarr."""
        logger.info("--> Configuring Bazarr...")
        base_url = URLS["bazarr"]
        headers = {"X-Api-Key": BAZARR_API_KEY}

        sonarr_parsed = urllib.parse.urlparse(URLS["sonarr"])
        radarr_parsed = urllib.parse.urlparse(URLS["radarr"])

        # Sonarr settings in Bazarr
        sonarr_config = {
            "ip": sonarr_parsed.hostname or "sonarr",
            "port": str(sonarr_parsed.port or 8989),
            "base_url": "",
            "ssl": False,
            "apikey": SONARR_API_KEY,
            "enabled": True,
        }
        http_request(
            f"{base_url}/api/sonarr", method="POST", data=sonarr_config, headers=headers
        )

        # Radarr settings in Bazarr
        radarr_config = {
            "ip": radarr_parsed.hostname or "radarr",
            "port": str(radarr_parsed.port or 7878),
            "base_url": "",
            "ssl": False,
            "apikey": RADARR_API_KEY,
            "enabled": True,
        }
        http_request(
            f"{base_url}/api/radarr", method="POST", data=radarr_config, headers=headers
        )
        logger.info("Bazarr connected to Sonarr and Radarr.")

    def verify_jellyfin(self):
        """Verifies Jellyfin health and inspects transcoding hardware."""
        logger.info("--> Verifying Jellyfin...")
        status, info, _ = http_request(f"{URLS['jellyfin']}/System/Info/Public")
        if status == 200 and isinstance(info, dict):
            logger.info(
                f"Jellyfin Server: {info.get('ServerName', 'Jellyfin')} (Version: {info.get('Version', 'unknown')})"
            )
        else:
            logger.info("Jellyfin is accessible.")

    def _jellyfin_auth_header(self, token: str = "") -> dict[str, str]:
        """Build the MediaBrowser X-Emby-Authorization header."""
        parts = [
            'MediaBrowser Client="Taiflix-Wire"',
            'Device="taiflix-wire"',
            'DeviceId="taiflix-servarr-wire"',
            'Version="1.0.0"',
        ]
        if token:
            parts.append(f'Token="{token}"')
        return {"X-Emby-Authorization": ", ".join(parts)}

    def _jellyfin_login(self) -> str | None:
        """Authenticate to Jellyfin and return the AccessToken."""
        base = URLS["jellyfin"]
        self._jellyfin_token: str | None = None
        # Jellyfin serves an HTML migration status page (HTTP 200) while
        # it's still applying first-boot DB migrations. /System/Info/Public
        # only returns JSON once migrations finish. Poll until we get a
        # real JSON dict, otherwise every downstream call gets HTML and
        # silently fails.
        public: Any = None
        deadline = time.monotonic() + 300  # 5 minutes
        while time.monotonic() < deadline:
            s, body, _ = http_request(f"{base}/System/Info/Public")
            if s == 200 and isinstance(body, dict):
                public = body
                break
            logger.info(
                f"Jellyfin not API-ready yet (status={s}, "
                f"body_type={type(body).__name__}); retrying..."
            )
            time.sleep(5)
        if not isinstance(public, dict):
            logger.warning(
                "Timed out waiting for Jellyfin to serve JSON from "
                "/System/Info/Public; cannot determine first-run state."
            )
            return None
        wizard_done = bool(public.get("StartupWizardCompleted"))

        if not wizard_done:
            logger.info(
                "Jellyfin first-run detected; creating first admin via /Startup/FirstUser..."
            )
            firstuser_payload = {
                "Name": JELLYFIN_USERNAME,
                "Password": JELLYFIN_ADMIN_PASSWORD,
            }
            status, body, _ = http_request(
                f"{base}/Startup/FirstUser",
                method="POST",
                data=firstuser_payload,
                headers=self._jellyfin_auth_header(),
            )
            if status == 200 and isinstance(body, dict):
                token = body.get("AccessToken") or body.get("Token")
                if token:
                    logger.info(
                        f"Created admin '{JELLYFIN_USERNAME}' via first-run, using returned token."
                    )
                    self._jellyfin_token = token
                    return token
                logger.warning(
                    "/Startup/FirstUser returned 200 but no token; falling back to login"
                )
            else:
                logger.warning(
                    f"/Startup/FirstUser returned {status} body={body}; trying login"
                )

            # Also submit configuration + remote access so the wizard
            # moves to a complete state. Safe to call repeatedly; Jellyfin
            # ignores unknown / redundant fields.
            for ep, payload in (
                (
                    "/Startup/Configuration",
                    {
                        "UICulture": "en-US",
                        "MetadataCountryCode": "US",
                        "PreferredMetadataLanguage": "en",
                    },
                ),
                (
                    "/Startup/RemoteAccess",
                    {"EnableRemoteAccess": False, "EnableAutomaticPortMapping": False},
                ),
            ):
                s, _, _ = http_request(
                    f"{base}{ep}",
                    method="POST",
                    data=payload,
                    headers=self._jellyfin_auth_header(),
                )
                if s not in (200, 204):
                    logger.warning(f"{ep} returned {s} (continuing)")

        # Try empty password first (for users seeded by seed_jellyfin_admin_if_missing
        # with NULL password), then fall back to the real password (for users created
        # manually via the UI). Jellyfin's DefaultAuthenticationProvider accepts empty
        # only when BOTH stored and supplied are empty.
        for pw_attempt in ("", JELLYFIN_ADMIN_PASSWORD):
            auth_payload = {
                "Username": JELLYFIN_USERNAME,
                "Pw": pw_attempt,
            }
            status, body, _ = http_request(
                f"{base}/Users/AuthenticateByName",
                method="POST",
                data=auth_payload,
                headers=self._jellyfin_auth_header(),
            )
            if status == 200 and isinstance(body, dict):
                token = body.get("AccessToken") or body.get("Token")
                if token:
                    label = "empty" if pw_attempt == "" else "real"
                    logger.info(
                        f"Authenticated to Jellyfin as '{JELLYFIN_USERNAME}' "
                        f"(using {label} password)."
                    )
                    self._jellyfin_token = token
                    return token
        logger.warning(
            f"Jellyfin login failed (tried empty + real password; last status={status}, body={body})"
        )
        return None

    def configure_jellyfin_libraries(self):
        """Create Jellyfin libraries for movies / tv / music (idempotent).

        Jellyfin's public API has stable endpoints for this:
          * POST /Startup/Configuration   — first-run admin (only if needed)
          * POST /Users/AuthenticateByName — get token (X-Emby-Authorization)
          * GET  /Library/VirtualFolders    — list existing
          * POST /Library/VirtualFolders    — create new
        """
        logger.info("--> Configuring Jellyfin libraries...")
        base = URLS["jellyfin"].rstrip("/")
        token = self._jellyfin_login()
        if not token:
            logger.warning("Skipping Jellyfin library setup (no auth token).")
            return
        auth_headers = self._jellyfin_auth_header(token)

        # 1. List existing libraries
        status, existing, _ = http_request(
            f"{base}/Library/VirtualFolders", headers=auth_headers
        )
        existing_names = set()
        if status == 200 and isinstance(existing, list):
            existing_names = {
                item.get("Name") for item in existing if isinstance(item, dict)
            }

        # 2. Parse desired libraries from env
        try:
            desired = json.loads(JELLYFIN_LIBRARIES_JSON)
            if not isinstance(desired, list):
                raise TypeError("JELLYFIN_LIBRARIES_JSON must be a JSON array")
        except (json.JSONDecodeError, TypeError) as exc:
            logger.warning(f"Invalid JELLYFIN_LIBRARIES_JSON, skipping: {exc}")
            return

        # 3. Create each missing library
        for lib in desired:
            name = lib.get("name")
            ctype = lib.get("collectionType")
            paths = lib.get("paths", [])
            if not name or not ctype or not paths:
                logger.warning(f"Skipping malformed library entry: {lib}")
                continue
            if name in existing_names:
                logger.info(f"Library '{name}' already exists, skipping.")
                continue
            payload = {
                "name": name,
                "collectionType": ctype,
                "paths": paths,
                "refreshStatus": "None",
                "preferredMetadataLanguage": "en",
                "preferredImageLanguage": "en",
            }
            status, body, _ = http_request(
                f"{base}/Library/VirtualFolders",
                method="POST",
                data=payload,
                headers=auth_headers,
            )
            if status in (200, 201, 204):
                logger.info(f"Library '{name}' created (type={ctype}, paths={paths}).")
            else:
                logger.warning(
                    f"Failed to create library '{name}' (status={status} body={body})"
                )

    def configure_jellyseerr(self, jellyfin_token: str | None):
        """Wire Jellyseerr to Jellyfin + Radarr + Sonarr. Best-effort.
        Performs first-run setup via the setup API, then POSTs the three
        server connections. If Jellyfin admin is missing, logs and skips.
        """
        if not jellyfin_token:
            logger.warning("Skipping Jellyseerr wiring (no Jellyfin admin token yet).")
            return
        base = URLS["jellyseerr"].rstrip("/")
        api = f"{base}/api/v1"

        # 1. First-run setup if needed (POST /setup)
        s, body, _ = http_request(f"{api}/setup")
        if isinstance(body, dict) and body.get("setupRequired") is True:
            logger.info("Jellyseerr first-run setup required; submitting...")
            setup_payload = {
                "username": JELLYFIN_USERNAME,
                "password": JELLYFIN_ADMIN_PASSWORD,
            }
            # The endpoint varies by fork/version; try the common ones
            for ep in ("/setup/finish", "/setup"):
                http_request(f"{api}{ep}", method="POST", data=setup_payload)
            time.sleep(2)

        # 2. Login to get API key (admin user in Jellyseerr is independent
        #    of Jellyfin; we use the same ADMIN_PASSWORD for parity)
        for user_pwd in (
            (JELLYFIN_USERNAME, JELLYFIN_ADMIN_PASSWORD),
            ("admin", JELLYFIN_ADMIN_PASSWORD),
        ):
            status, login, _ = http_request(
                f"{api}/auth/login",
                method="POST",
                data={"username": user_pwd[0], "password": user_pwd[1]},
            )
            if status == 200 and isinstance(login, dict):
                if "password" in login:  # jellyseerr-style login response
                    break

        # 3. Get current settings to know existing API keys
        s, main_settings, _ = http_request(f"{api}/settings/main")
        api_key = (
            main_settings.get("apiKey") if isinstance(main_settings, dict) else None
        )
        if not api_key:
            # Generate one
            s, key_resp, _ = http_request(
                f"{api}/settings/main/regenerate", method="POST"
            )
            if isinstance(key_resp, dict):
                api_key = key_resp.get("apiKey")
        if not api_key:
            logger.warning(
                "Jellyseerr setup didn't produce an API key; wiring skipped."
            )
            return
        auth = {"X-Api-Key": api_key}

        # 4. Configure Jellyfin, Radarr, Sonarr server connections
        jf = urllib.parse.urlparse(URLS["jellyfin"])
        rd = urllib.parse.urlparse(URLS["radarr"])
        sn = urllib.parse.urlparse(URLS["sonarr"])
        for label, port, url, key_env, kind, is_default in [
            ("Jellyfin", 8096, f"{jf.scheme}://{jf.hostname}", None, "jellyfin", True),
            (
                "Radarr",
                7878,
                f"{rd.scheme}://{rd.hostname}",
                RADARR_API_KEY,
                "radarr",
                False,
            ),
            (
                "Sonarr",
                8989,
                f"{sn.scheme}://{sn.hostname}",
                SONARR_API_KEY,
                "sonarr",
                False,
            ),
        ]:
            payload: dict[str, Any] = {
                "name": label,
                "hostname": urllib.parse.urlparse(url).hostname,
                "port": port,
                "ssl": (urllib.parse.urlparse(url).scheme or "http") == "https",
                "baseUrl": "",
                "enabled": True,
                "is4k": False,
                "isDefault": is_default,
                "activeProfileId": 1,
            }
            if kind == "jellyfin":
                payload["url"] = url
                payload["apiKey"] = jellyfin_token
                payload["externalHost"] = url
                payload["jellyfinLibraryId"] = None
                payload["userName"] = JELLYFIN_USERNAME
            else:
                payload["apiKey"] = key_env
            s, body, _ = http_request(
                f"{api}/settings/{kind}", method="POST", data=payload, headers=auth
            )
            if s in (200, 201):
                logger.info(f"Jellyseerr: connected to {label}.")
            else:
                logger.warning(f"Jellyseerr -> {label} failed status={s} body={body}")


def seed_jellyfin_admin_if_missing() -> bool:
    """Pre-seed a Jellyfin admin user directly in the SQLite DB when none
    exists. Used because Jellyfin v10.11's POST /Startup/FirstUser returns
    405, so there's no API path to create the first admin.

    Runs as a backup to the standard login flow. Safe and idempotent:
      * No-op if /config/data/jellyfin.db doesn't exist yet (Jellyfin
        hasn't run its first-boot migrations).
      * No-op if any user already exists (won't overwrite manual setup).
      * No-op if insert fails (logs and lets _jellyfin_login try empty
        password).

    Returns True if a user was inserted, False otherwise.
    """
    import sqlite3
    import uuid as _uuid

    db_path = "/config/data/jellyfin.db"
    if not os.path.exists(db_path):
        logger.info(
            "Jellyfin DB not present yet (no %s); skipping seed.",
            db_path,
        )
        return False
    try:
        conn = sqlite3.connect(db_path, timeout=10)
    except sqlite3.DatabaseError as exc:
        logger.warning(f"Cannot open Jellyfin DB: {exc}")
        return False
    try:
        # Wait briefly for migrations to complete
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            try:
                has_users = conn.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='Users'"
                ).fetchone()
                if has_users:
                    break
            except sqlite3.DatabaseError:
                pass
            time.sleep(2)
        else:
            logger.warning("Users table never appeared; giving up on seed.")
            return False

        existing = conn.execute(
            "SELECT Id FROM Users WHERE Username = ? OR NormalizedUsername = ?",
            (JELLYFIN_USERNAME, JELLYFIN_USERNAME.upper()),
        ).fetchone()
        if existing:
            logger.info(
                f"Jellyfin user '{JELLYFIN_USERNAME}' already exists (id={existing[0]}); "
                "skipping seed."
            )
            return False

        cols_info = conn.execute("PRAGMA table_info(Users)").fetchall()
        cols = [r[1] for r in cols_info]
        notnull_by_col = {r[1]: r[3] for r in cols_info}

        seed_defaults = {
            "Username": JELLYFIN_USERNAME,
            "NormalizedUsername": JELLYFIN_USERNAME.upper(),
            "Password": None,
            "MustUpdatePassword": 0,
            "AuthenticationProviderId": "Default",
            "PasswordResetProviderId": "Default",
            "InvalidLoginAttemptCount": 0,
            "MaxActiveSessions": 0,
            "SubtitleMode": 0,
            "PlayDefaultAudioTrack": 1,
            "EnableLocalPassword": 1,
            "EnableUserPreferenceAccess": 1,
            "InternalId": 0,
            "SyncPlayAccess": 0,
            "RowVersion": 1,
        }
        user_id = str(_uuid.uuid4())
        values = []
        for col in cols:
            if col == "Id":
                values.append(user_id)
                continue
            if col in seed_defaults:
                values.append(seed_defaults[col])
            else:
                values.append(None if notnull_by_col.get(col, 0) == 0 else 0)

        placeholders = ",".join("?" * len(cols))
        sql = f"INSERT INTO Users ({',{cols}'.replace("{',{'", ",")}) VALUES ({placeholders})".replace(
            f",{cols[0]}", f",{cols[0]}"
        )
        # Simpler: just join columns
        sql = f"INSERT INTO Users ({','.join(cols)}) VALUES ({placeholders})"
        conn.execute(sql, values)
        conn.commit()
        logger.info(f"Seeded Jellyfin admin user '{JELLYFIN_USERNAME}' (id={user_id})")

        # Try to grant IsAdministrator permission (best-effort)
        try:
            perm_cols_info = conn.execute("PRAGMA table_info(Permissions)").fetchall()
            perm_cols = {r[1] for r in perm_cols_info}
            fk_col = next(
                (
                    c
                    for c in (
                        "Permission_Permissions_Guid",
                        "UserId",
                        "User_id",
                        "UserId1",
                    )
                    if c in perm_cols
                ),
                None,
            )
            if fk_col:
                already = conn.execute(
                    f"SELECT 1 FROM Permissions WHERE {fk_col} = ? AND Kind = 0 LIMIT 1",
                    (user_id,),
                ).fetchone()
                if not already:
                    row = {"Kind": 0, "Value": 1, "RowVersion": 1, fk_col: user_id}
                    insert_cols = [c for c in row if c in perm_cols]
                    if "Id" in perm_cols:
                        insert_cols = [c for c in insert_cols if c != "Id"]
                    placeholders2 = ",".join("?" * len(insert_cols))
                    conn.execute(
                        f"INSERT INTO Permissions ({','.join(insert_cols)}) "
                        f"VALUES ({placeholders2})",
                        [row[c] for c in insert_cols],
                    )
                    conn.commit()
                    logger.info("Granted Jellyfin admin IsAdministrator permission.")
        except sqlite3.DatabaseError as exc:
            logger.warning(
                f"Could not grant admin via Permissions ({exc}); "
                "user can still log in, wire will upgrade later."
            )
        return True
    finally:
        conn.close()


def main():
    logger.info("==========================================================")
    logger.info("   Taiflix Servarr Cross-Service Auto-Wiring Starting    ")
    logger.info("==========================================================")

    # 1. Wait for services to be ready
    wait_for_service("qBittorrent", URLS["qbittorrent"], "/api/v2/app/version")
    wait_for_service("Flaresolverr", URLS["flaresolverr"], "/health")
    wait_for_service(
        "Prowlarr", URLS["prowlarr"], "/api/v1/system/status", PROWLARR_API_KEY
    )
    wait_for_service("Sonarr", URLS["sonarr"], "/api/v3/system/status", SONARR_API_KEY)
    wait_for_service("Radarr", URLS["radarr"], "/api/v3/system/status", RADARR_API_KEY)
    wait_for_service("Lidarr", URLS["lidarr"], "/api/v1/system/status", LIDARR_API_KEY)
    wait_for_service("Bazarr", URLS["bazarr"], "/api/system/status", BAZARR_API_KEY)
    wait_for_service("Jellyfin", URLS["jellyfin"], "/health")
    wait_for_service("Jellyseerr", URLS["jellyseerr"], "/api/v1/status")

    # 2. Execute wiring orchestration
    wire = ServarrWire()
    try:
        wire.configure_qbittorrent()
    except Exception as e:
        logger.warning(f"qBittorrent wiring step failed: {e}")

    try:
        wire.configure_prowlarr()
    except Exception as e:
        logger.warning(f"Prowlarr wiring step failed: {e}")

    try:
        wire.configure_arr_service(
            "Sonarr", URLS["sonarr"], SONARR_API_KEY, "tv-sonarr", "/media/tv"
        )
    except Exception as e:
        logger.warning(f"Sonarr wiring step failed: {e}")

    try:
        wire.configure_arr_service(
            "Radarr", URLS["radarr"], RADARR_API_KEY, "radarr", "/media/movies"
        )
    except Exception as e:
        logger.warning(f"Radarr wiring step failed: {e}")

    try:
        wire.configure_arr_service(
            "Lidarr", URLS["lidarr"], LIDARR_API_KEY, "lidarr", "/media/music"
        )
    except Exception as e:
        logger.warning(f"Lidarr wiring step failed: {e}")

    try:
        wire.configure_bazarr()
    except Exception as e:
        logger.warning(f"Bazarr wiring step failed: {e}")

    try:
        wire.verify_jellyfin()
    except Exception as e:
        logger.warning(f"Jellyfin verify step failed: {e}")

    try:
        seed_jellyfin_admin_if_missing()
    except Exception as e:
        logger.warning(f"Jellyfin seed step failed: {e}")

    try:
        wire.configure_jellyfin_libraries()
    except Exception as e:
        logger.warning(f"Jellyfin library wiring step failed: {e}")

    # Wire Sonarr/Radarr -> Jellyfin notify-on-import (needs Jellyfin token).
    # Token comes from configure_jellyfin_libraries; if that failed the notify
    # step is a no-op.
    jf_token = getattr(wire, "_jellyfin_token", None)
    if jf_token:
        for label, base_url, api_key in [
            ("Sonarr", URLS["sonarr"], SONARR_API_KEY),
            ("Radarr", URLS["radarr"], RADARR_API_KEY),
        ]:
            try:
                wire.configure_arr_jellyfin_notify(label, base_url, api_key, jf_token)
            except Exception as e:
                logger.warning(f"{label} -> Jellyfin notify failed: {e}")
    else:
        logger.info(
            "Skipping Sonarr/Radarr -> Jellyfin notify (no Jellyfin admin token)."
        )

    try:
        wire.configure_jellyseerr(jf_token)
    except Exception as e:
        logger.warning(f"Jellyseerr wiring step failed: {e}")

    logger.info("==========================================================")
    logger.info("   Taiflix Servarr Cross-Service Auto-Wiring COMPLETE    ")
    logger.info("==========================================================")
    sys.exit(0)


if __name__ == "__main__":
    main()
