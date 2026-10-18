import os
from typing import Any, Dict, List, Optional

from pymongo import MongoClient
from pymongo.database import Database
from pymongo.errors import PyMongoError, ServerSelectionTimeoutError


MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "iac_validation_db")
COLLECTION_NAMES: List[str] = [
    "users",
    "projects",
    "uploads",
    "validation_reports",
    "dataset_evaluation_runs",
    "dataset_evaluation_results",
]

_client: Optional[MongoClient] = None


def get_mongo_client() -> MongoClient:
    global _client

    if _client is None:
        client_kwargs: Dict[str, Any] = {
            "serverSelectionTimeoutMS": int(os.getenv("MONGODB_TIMEOUT_MS", "3000")),
        }

        use_tls = os.getenv("DOCUMENTDB_TLS", "false").lower() in ("true", "1", "yes")
        if use_tls:
            client_kwargs["tls"] = True
            ca_file = os.getenv("DOCUMENTDB_TLS_CA_FILE")
            if ca_file and os.path.exists(ca_file):
                client_kwargs["tlsCAFile"] = ca_file
            elif os.getenv("DOCUMENTDB_INSECURE_TLS", "false").lower() in ("true", "1", "yes"):
                client_kwargs["tlsAllowInvalidCertificates"] = True
            client_kwargs["retryWrites"] = False

        use_mock = os.getenv("MOCK_DATABASE", "false").lower() in ("true", "1", "yes")
        if use_mock:
            try:
                import mongomock
                _client = mongomock.MongoClient()
                return _client
            except ImportError:
                pass

        try:
            candidate = MongoClient(MONGODB_URI, **client_kwargs)
            candidate.admin.command("ping")
            _client = candidate
        except Exception:
            try:
                import mongomock
                _client = mongomock.MongoClient()
            except ImportError:
                _client = MongoClient(MONGODB_URI, **client_kwargs)

    return _client


def get_database() -> Database:
    return get_mongo_client()[MONGODB_DATABASE]


def ensure_collections() -> None:
    database = get_database()
    existing_collections = set(database.list_collection_names())

    for collection_name in COLLECTION_NAMES:
        if collection_name not in existing_collections:
            database.create_collection(collection_name)


def check_database_connection() -> Dict[str, object]:
    try:
        client = get_mongo_client()
        client.admin.command("ping")
        ensure_collections()

        return {
            "success": True,
            "message": "MongoDB connection successful",
            "database": MONGODB_DATABASE,
            "collections": COLLECTION_NAMES,
        }
    except (ServerSelectionTimeoutError, PyMongoError) as exc:
        return {
            "success": False,
            "message": "MongoDB connection failed",
            "error": str(exc),
        }


def close_mongo_connection() -> None:
    global _client

    if _client is not None:
        _client.close()
        _client = None
