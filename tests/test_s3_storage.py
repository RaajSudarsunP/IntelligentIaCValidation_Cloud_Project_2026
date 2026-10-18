"""Tests for Dual-mode S3 and Local Storage Provider."""
from unittest.mock import MagicMock
from src.backend.storage.s3_storage import (
    LocalStorageProvider,
    S3StorageProvider,
    ResilientStorageManager,
)


def test_local_storage_provider(tmp_path):
    provider = LocalStorageProvider(base_dir=tmp_path)
    content = b"resource \"aws_s3_bucket\" \"b\" {}"
    filename = "test.tf"

    meta = provider.save_file(content, filename)
    assert meta["storage_type"] == "local"
    assert meta["size_bytes"] == len(content)

    retrieved = provider.read_file(filename)
    assert retrieved == content

    deleted = provider.delete_file(filename)
    assert deleted is True
    assert not (tmp_path / filename).exists()


def test_s3_storage_provider_with_mock():
    mock_boto = MagicMock()
    mock_body = MagicMock()
    mock_body.read.return_value = b"sample s3 content"
    mock_boto.get_object.return_value = {"Body": mock_body}

    provider = S3StorageProvider(
        bucket_name="test-iac-bucket",
        region_name="us-east-1",
        boto3_client=mock_boto,
    )

    meta = provider.save_file(b"sample s3 content", "cloud.tf")
    assert meta["storage_type"] == "s3"
    assert meta["s3_bucket"] == "test-iac-bucket"
    assert "cloud.tf" in meta["s3_key"]
    assert mock_boto.put_object.called

    content = provider.read_file(meta["s3_key"])
    assert content == b"sample s3 content"

    provider.delete_file(meta["s3_key"])
    assert mock_boto.delete_object.called


def test_resilient_storage_manager_fallback(tmp_path):
    failing_s3 = MagicMock()
    failing_s3.save_file.side_effect = RuntimeError("S3 connection error")

    local = LocalStorageProvider(base_dir=tmp_path)
    manager = ResilientStorageManager(
        primary_provider=failing_s3,
        fallback_provider=local,
    )

    meta = manager.save_file(b"fallback data", "fallback.tf")
    assert meta["storage_type"] == "local"
    assert (tmp_path / "fallback.tf").exists()
