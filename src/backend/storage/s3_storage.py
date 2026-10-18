"""Dual-mode Storage Provider for Intelligent IaC Validation.

Supports Amazon S3 for cloud deployment and seamlessly falls back to
local filesystem storage for local development and offline environments.
"""
from __future__ import annotations

import logging
import os
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

BACKEND_DIR = Path(__file__).resolve().parents[1]
DEFAULT_LOCAL_UPLOAD_DIR = BACKEND_DIR / "storage" / "uploads"


class StorageProvider(ABC):
    """Abstract interface for storing and retrieving IaC templates and reports."""

    @abstractmethod
    def save_file(
        self,
        content: bytes,
        filename: str,
        content_type: str = "text/plain",
    ) -> Dict[str, Any]:
        """Save file content and return storage metadata."""
        raise NotImplementedError

    @abstractmethod
    def read_file(self, identifier: str) -> bytes:
        """Read file content by file path or S3 key."""
        raise NotImplementedError

    @abstractmethod
    def delete_file(self, identifier: str) -> bool:
        """Delete file by file path or S3 key."""
        raise NotImplementedError


class LocalStorageProvider(StorageProvider):
    """Local filesystem storage provider for offline and development mode."""

    def __init__(self, base_dir: Path | None = None) -> None:
        self.base_dir = Path(base_dir or DEFAULT_LOCAL_UPLOAD_DIR)
        self.base_dir.mkdir(parents=True, exist_ok=True)

    def save_file(
        self,
        content: bytes,
        filename: str,
        content_type: str = "text/plain",
    ) -> Dict[str, Any]:
        target_path = self.base_dir / filename
        target_path.write_bytes(content)
        return {
            "storage_type": "local",
            "file_path": str(target_path),
            "filename": filename,
            "size_bytes": len(content),
            "s3_bucket": None,
            "s3_key": None,
        }

    def read_file(self, identifier: str) -> bytes:
        path = Path(identifier)
        if not path.is_absolute():
            path = self.base_dir / identifier
        if not path.exists():
            raise FileNotFoundError(f"File not found: {identifier}")
        return path.read_bytes()

    def delete_file(self, identifier: str) -> bool:
        path = Path(identifier)
        if not path.is_absolute():
            path = self.base_dir / identifier
        if path.exists():
            path.unlink(missing_ok=True)
            return True
        return False


class S3StorageProvider(StorageProvider):
    """Amazon S3 storage provider using boto3."""

    def __init__(
        self,
        bucket_name: str,
        region_name: str = "us-east-1",
        boto3_client: Any = None,
        prefix: str = "uploads",
    ) -> None:
        self.bucket_name = bucket_name
        self.region_name = region_name
        self.prefix = prefix.strip("/")

        if boto3_client is not None:
            self._client = boto3_client
        else:
            import boto3
            self._client = boto3.client("s3", region_name=region_name)

    def save_file(
        self,
        content: bytes,
        filename: str,
        content_type: str = "text/plain",
    ) -> Dict[str, Any]:
        key = f"{self.prefix}/{filename}" if self.prefix else filename
        self._client.put_object(
            Bucket=self.bucket_name,
            Key=key,
            Body=content,
            ContentType=content_type,
        )
        return {
            "storage_type": "s3",
            "file_path": f"s3://{self.bucket_name}/{key}",
            "filename": filename,
            "size_bytes": len(content),
            "s3_bucket": self.bucket_name,
            "s3_key": key,
        }

    def read_file(self, identifier: str) -> bytes:
        key = identifier
        if key.startswith("s3://"):
            parts = key[5:].split("/", 1)
            if len(parts) == 2:
                key = parts[1]
        response = self._client.get_object(Bucket=self.bucket_name, Key=key)
        return response["Body"].read()

    def delete_file(self, identifier: str) -> bool:
        key = identifier
        if key.startswith("s3://"):
            parts = key[5:].split("/", 1)
            if len(parts) == 2:
                key = parts[1]
        self._client.delete_object(Bucket=self.bucket_name, Key=key)
        return True


class ResilientStorageManager:
    """Storage manager that defaults to S3 if configured, with graceful local fallback."""

    def __init__(
        self,
        primary_provider: Optional[StorageProvider] = None,
        fallback_provider: Optional[StorageProvider] = None,
    ) -> None:
        self.primary = primary_provider or get_configured_storage_provider()
        self.fallback = fallback_provider or LocalStorageProvider()

    def save_file(
        self,
        content: bytes,
        filename: str,
        content_type: str = "text/plain",
    ) -> Dict[str, Any]:
        try:
            return self.primary.save_file(content, filename, content_type)
        except Exception as exc:
            logger.warning("Primary storage provider failed (%s), using local fallback", exc)
            return self.fallback.save_file(content, filename, content_type)

    def read_file(self, identifier: str) -> bytes:
        try:
            return self.primary.read_file(identifier)
        except Exception as exc:
            logger.warning("Primary storage read failed (%s), trying fallback", exc)
            return self.fallback.read_file(identifier)

    def delete_file(self, identifier: str) -> bool:
        try:
            return self.primary.delete_file(identifier)
        except Exception:
            return self.fallback.delete_file(identifier)


def get_configured_storage_provider() -> StorageProvider:
    """Factory creating the appropriate storage provider from environment variables."""
    use_s3 = os.getenv("USE_S3_STORAGE", "false").lower() in ("true", "1", "yes")
    bucket = os.getenv("S3_BUCKET_NAME") or os.getenv("AWS_S3_BUCKET")
    region = os.getenv("AWS_REGION", "us-east-1")

    if use_s3 and bucket:
        try:
            return S3StorageProvider(bucket_name=bucket, region_name=region)
        except Exception as exc:
            logger.warning("Failed to initialize S3 storage provider (%s); using local", exc)
            return LocalStorageProvider()

    return LocalStorageProvider()


# Global default instance
storage_manager = ResilientStorageManager()
