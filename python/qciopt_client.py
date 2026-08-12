"""Small Qatalyst REST client used internally by QCIOpt.jl.

The public ``qci-client`` distribution currently pins NetworkX below version 3,
which conflicts with D-Wave Ocean. QCIOpt only needs a narrow part of that
client, so this module implements that part directly with requests and numpy.
Its request and response shapes track ``qci-client`` 5.0.0.
"""

from __future__ import annotations

import os
import time
from datetime import datetime, timezone
from types import SimpleNamespace
from typing import Any
from urllib.parse import urljoin

import numpy as np
import requests
from requests.adapters import HTTPAdapter, Retry

__version__ = "qciopt-bridge-0.2.0"
__qci_client_parity_version__ = "5.0.0"

_BACKOFF_FACTOR = 2
_CHUNK_SIZE = 10_000
_FINAL_JOB_STATUSES = {"COMPLETED", "ERRORED", "CANCELLED"}
_RESULTS_CHECK_INTERVAL_SECONDS = 2.5
_RETRYABLE_STATUS_CODES = (502, 503, 504)
_RETRY_TOTAL = 7


def _raise_for_status(response: requests.Response) -> None:
    """Raise an HTTP error that retains the provider response body."""
    try:
        response.raise_for_status()
    except requests.HTTPError as error:
        raise requests.HTTPError(
            f"{error} with response body: {response.text}"
        ) from error


def _only_file_config(file: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    configs = file["file_config"]
    if len(configs) != 1:
        raise ValueError("file_config must contain exactly one file type")

    file_type = next(iter(configs))
    return file_type, configs[file_type]


def _data_to_json(file: dict[str, Any]) -> dict[str, Any]:
    """Convert QCIOpt matrix or polynomial data to the Files API format."""
    file_type, config = _only_file_config(file)

    if file_type in {"constraints", "hamiltonian", "objective", "qubo"}:
        matrix = np.asarray(config["data"])
        if matrix.ndim != 2:
            raise ValueError(f"{file_type} data must be a two-dimensional matrix")

        rows, columns = matrix.shape
        row_indices, column_indices = np.nonzero(matrix)
        data = [
            {
                "i": int(i),
                "j": int(j),
                "val": float(matrix[i, j]),
            }
            for i, j in zip(row_indices, column_indices)
        ]
        converted: dict[str, Any] = {"data": data}

        if file_type == "constraints":
            converted["num_constraints"] = rows
            converted["num_variables"] = columns - 1
        else:
            converted["num_variables"] = rows
    elif file_type == "polynomial":
        converted = dict(config)
    else:
        raise ValueError(f"unsupported QCIOpt file type: {file_type!r}")

    return {
        "file_name": file.get("file_name", f"{file_type}.json"),
        "file_config": {file_type: converted},
    }


def _metadata_body(file: dict[str, Any]) -> dict[str, Any]:
    file_type, config = _only_file_config(file)
    metadata_keys = {
        "constraints": ("num_constraints", "num_variables"),
        "hamiltonian": ("num_variables",),
        "objective": ("num_variables",),
        "polynomial": ("min_degree", "max_degree", "num_variables"),
        "qubo": ("num_variables",),
    }

    try:
        keys = metadata_keys[file_type]
    except KeyError as error:
        raise ValueError(f"unsupported QCIOpt file type: {file_type!r}") from error

    return {
        "file_name": file.get("file_name", f"{file_type}.json"),
        "file_config": {
            file_type: {key: config[key] for key in keys},
        },
    }


def _file_parts(file: dict[str, Any]):
    file_type, config = _only_file_config(file)
    data = config["data"]

    for part_number, start in enumerate(
        range(0, max(1, len(data)), _CHUNK_SIZE),
        start=1,
    ):
        yield (
            {
                "file_config": {
                    file_type: {
                        "data": data[start : start + _CHUNK_SIZE],
                    }
                }
            },
            part_number,
        )


class AuthClient:
    """Authenticate QCI refresh tokens and cache their short-lived access token."""

    def __init__(
        self,
        *,
        url: str | None = None,
        api_token: str | None = None,
        timeout: float | None = None,
    ):
        self.url = (url or os.getenv("QCI_API_URL", "")).rstrip("/") + "/"
        if self.url == "/":
            raise ValueError("must specify url or QCI_API_URL")

        self.api_token = api_token or os.getenv("QCI_TOKEN", "")
        if not self.api_token:
            raise AssertionError("must specify api_token or QCI_TOKEN")

        self.timeout = timeout
        self._access_token_info: dict[str, Any] | None = None

    @property
    def access_tokens_url(self) -> str:
        return urljoin(self.url, "auth/v1/access-tokens/")

    def post_access_tokens(self) -> dict[str, Any]:
        response = requests.post(
            self.access_tokens_url,
            headers={"Content-Type": "application/json", "Connection": "close"},
            json={"refresh_token": self.api_token},
            timeout=self.timeout,
        )
        _raise_for_status(response)
        return response.json()

    def _access_token_is_expiring(self) -> bool:
        if self._access_token_info is None:
            return True

        expires_at = self._access_token_info.get("expires_at_rfc3339")
        if not expires_at:
            return True

        expiration = datetime.strptime(expires_at, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
        return (expiration - datetime.now(timezone.utc)).total_seconds() < 600

    @property
    def access_token(self) -> str:
        if self._access_token_is_expiring():
            self._access_token_info = self.post_access_tokens()

        return self._access_token_info["access_token"]

    @property
    def headers_without_connection_close(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.access_token}",
            "Content-Type": "application/json",
        }


class OptimizationClient:
    """Subset of the Qatalyst optimization client used by QCIOpt."""

    def __init__(
        self,
        *,
        url: str | None = None,
        api_token: str | None = None,
        timeout: float | None = None,
    ):
        self._auth_client = AuthClient(
            url=url,
            api_token=api_token,
            timeout=timeout,
        )
        self._session = requests.Session()
        self._session.mount(
            "https://",
            HTTPAdapter(
                max_retries=Retry(
                    total=_RETRY_TOTAL,
                    backoff_factor=_BACKOFF_FACTOR,
                    status_forcelist=_RETRYABLE_STATUS_CODES,
                )
            ),
        )

    @property
    def url(self) -> str:
        return self._auth_client.url

    @property
    def timeout(self) -> float | None:
        return self._auth_client.timeout

    @property
    def jobs_url(self) -> str:
        return urljoin(self.url, "optimization/v1/jobs")

    @property
    def files_url(self) -> str:
        return urljoin(self.url, "optimization/v1/files")

    @property
    def headers(self) -> dict[str, str]:
        return self._auth_client.headers_without_connection_close

    def _job_url(self, job_id: str) -> str:
        return f"{self.jobs_url}/{job_id}"

    def _file_url(self, file_id: str) -> str:
        return f"{self.files_url}/{file_id}"

    def upload_file(self, *, file: dict[str, Any]) -> dict[str, str]:
        """Upload file metadata and chunked contents, returning its file ID."""
        converted = _data_to_json(file)
        response = self._session.post(
            self.files_url,
            headers=self.headers,
            timeout=self.timeout,
            json=_metadata_body(converted),
        )
        _raise_for_status(response)
        file_id = response.json()["file_id"]

        for part, part_number in _file_parts(converted):
            response = self._session.patch(
                f"{self._file_url(file_id)}/contents/{part_number}",
                headers=self.headers,
                timeout=self.timeout,
                json=part,
            )
            _raise_for_status(response)

        return {"file_id": file_id}

    def download_file(self, *, file_id: str) -> dict[str, Any]:
        """Download and assemble a file's metadata and ordered content parts."""
        response = self._session.get(
            self._file_url(file_id),
            headers=self.headers,
            timeout=self.timeout,
        )
        _raise_for_status(response)
        file = response.json()
        file.pop("last_accessed_rfc3339", None)
        file.pop("upload_date_rfc3339", None)

        for part_number in range(1, file["num_parts"] + 1):
            response = self._session.get(
                f"{self._file_url(file_id)}/contents/{part_number}",
                headers=self.headers,
                timeout=self.timeout,
            )
            _raise_for_status(response)

            for file_type, part_config in response.json()["file_config"].items():
                target = file["file_config"].setdefault(file_type, {})
                for key, value in part_config.items():
                    target.setdefault(key, []).extend(value)

        return file

    def get_allocations(self) -> dict[str, Any]:
        """Return the caller's current QCI device allocations."""
        response = self._session.get(
            f"{self.jobs_url}/allocations",
            headers=self.headers,
            timeout=self.timeout,
        )
        _raise_for_status(response)
        return response.json()

    def submit_job(self, *, job_body: dict[str, Any]) -> dict[str, Any]:
        """Submit a prepared QCI job body without waiting for completion."""
        response = self._session.post(
            self.jobs_url,
            headers=self.headers,
            timeout=self.timeout,
            json=job_body,
        )
        _raise_for_status(response)
        return response.json()

    def get_job_status(self, *, job_id: str) -> dict[str, Any]:
        """Return the latest status for a submitted job."""
        response = self._session.get(
            f"{self._job_url(job_id)}/status",
            headers=self.headers,
            timeout=self.timeout,
        )
        _raise_for_status(response)
        return response.json()

    def get_job_response(self, *, job_id: str) -> dict[str, Any]:
        """Return the provider's job record for a submitted job."""
        response = self._session.get(
            self._job_url(job_id),
            headers=self.headers,
            timeout=self.timeout,
        )
        _raise_for_status(response)
        return response.json()

    def get_job_results(self, *, job_id: str) -> dict[str, Any]:
        """Return a job record, status, and assembled results when completed."""
        job_info = self.get_job_response(job_id=job_id)
        status = self.get_job_status(job_id=job_id)["status"]
        results = None

        if status == "COMPLETED":
            file = self.download_file(file_id=job_info["job_result"]["file_id"])
            _, results = _only_file_config(file)

        return {"job_info": job_info, "status": status, "results": results}

    def get_job_metrics(self, *, job_id: str) -> dict[str, Any]:
        """Return v2 job metrics, falling back to the legacy endpoint."""
        response = self._session.get(
            f"{self._job_url(job_id)}/metrics/v2",
            headers=self.headers,
            timeout=self.timeout,
        )
        if response.status_code == requests.codes.not_found:
            response = self._session.get(
                f"{self._job_url(job_id)}/metrics",
                headers=self.headers,
                timeout=self.timeout,
            )
        _raise_for_status(response)

        if response.json().get("job_metrics") is None:
            response = self._session.get(
                f"{self._job_url(job_id)}/metrics",
                headers=self.headers,
                timeout=self.timeout,
            )
            _raise_for_status(response)

        return response.json()

    def _log_dirac_allocation(self, verbose: bool) -> None:
        if not verbose:
            return

        allocation = self.get_allocations()["allocations"]["dirac"]
        message = f"Dirac allocation balance = {allocation['seconds']} s"
        if not allocation.get("metered", True):
            message += " (unmetered)"
        print(f"{datetime.now():%Y-%m-%d %H:%M:%S} - {message}")

    def build_job_body(
        self,
        *,
        job_type: str,
        job_params: dict[str, Any],
        qubo_file_id: str | None = None,
        hamiltonian_file_id: str | None = None,
        polynomial_file_id: str | None = None,
        job_name: str | None = None,
        job_tags: list[str] | None = None,
    ) -> dict[str, Any]:
        """Build the QUBO or integer-polynomial job body used by QCIOpt."""
        device_type = job_params.get("device_type")
        if device_type is None:
            raise ValueError("job_params must include device_type")

        device_config: dict[str, Any] = {}
        if "num_samples" in job_params:
            device_config["num_samples"] = job_params["num_samples"]

        if job_type == "sample-qubo":
            if device_type != "dirac-1":
                raise ValueError("sample-qubo is only supported on dirac-1")
            if not qubo_file_id:
                raise AssertionError("qubo_file_id is required for sample-qubo")

            problem_name = "quadratic_unconstrained_binary_optimization"
            problem_config = {"qubo_file_id": qubo_file_id}
        elif job_type == "sample-hamiltonian-integer":
            if device_type not in {"dirac-3", "dirac-3_qudit"}:
                raise ValueError(
                    "sample-hamiltonian-integer is only supported on dirac-3"
                )
            if "num_levels" not in job_params:
                raise AssertionError("num_levels is required")
            if bool(hamiltonian_file_id) == bool(polynomial_file_id):
                raise AssertionError(
                    "exactly one of hamiltonian_file_id or polynomial_file_id is required"
                )

            device_type = "dirac-3_qudit"
            device_config["num_levels"] = job_params["num_levels"]
            if "relaxation_schedule" in job_params:
                device_config["relaxation_schedule"] = job_params["relaxation_schedule"]

            problem_name = "qudit_hamiltonian_optimization"
            problem_config = (
                {"hamiltonian_file_id": hamiltonian_file_id}
                if hamiltonian_file_id
                else {"polynomial_file_id": polynomial_file_id}
            )
        else:
            raise ValueError(f"unsupported job_type: {job_type!r}")

        submission: dict[str, Any] = {
            "problem_config": {problem_name: problem_config},
            "device_config": {device_type: device_config},
        }
        if job_name is not None:
            submission["job_name"] = job_name
        if job_tags is not None:
            submission["job_tags"] = job_tags

        return {"job_submission": submission}

    def process_job(
        self,
        *,
        job_body: dict[str, Any],
        wait: bool = True,
        verbose: bool = True,
    ) -> dict[str, Any]:
        """Submit a job and optionally poll until a final result is available."""
        self._log_dirac_allocation(verbose)
        submitted = self.submit_job(job_body=job_body)
        job_id = submitted["job_id"]
        if verbose:
            print(
                f"{datetime.now():%Y-%m-%d %H:%M:%S} - Job submitted: job_id='{job_id}'"
            )

        if not wait:
            return submitted

        status = "SUBMITTED"
        while status not in _FINAL_JOB_STATUSES:
            latest = self.get_job_status(job_id=job_id)["status"]
            if latest != status and verbose:
                print(f"{datetime.now():%Y-%m-%d %H:%M:%S} - {latest}")
            status = latest
            if status not in _FINAL_JOB_STATUSES:
                time.sleep(_RESULTS_CHECK_INTERVAL_SECONDS)

        self._log_dirac_allocation(verbose)
        return self.get_job_results(job_id=job_id)


QciClient = OptimizationClient
auth = SimpleNamespace(client=SimpleNamespace(AuthClient=AuthClient))
