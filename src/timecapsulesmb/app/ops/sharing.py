from __future__ import annotations

from timecapsulesmb.app.confirmations import build_confirmation, require_confirmation
from timecapsulesmb.app.context import AppOperationContext
from timecapsulesmb.app.ops.common import load_request_config, resolve_request_connection, require_request_acpd_ready, require_request_no_disk_check
from timecapsulesmb.core.net import endpoint_host
from timecapsulesmb.device.sharing import SharingSettingsError, changed_settings, read_settings, write_settings
from timecapsulesmb.services.app import AppOperationError, OperationResult
from timecapsulesmb.services.reboot import reboot_device


def sharing_operation(params: dict[str, object], context: AppOperationContext) -> OperationResult:
    config = load_request_config(params, context)
    connection = resolve_request_connection(config, context, allow_empty_password=False)
    try:
        context.stage("read_sharing")
        current = read_settings(connection)
        action = params.get("action", "read")
        if action == "read":
            return OperationResult(True, current.public())
        if action != "apply":
            raise SharingSettingsError("Choose a valid sharing action.")
        desired = changed_settings(current, params.get("changes"), params.get("credentials"))
        require_confirmation(params, build_confirmation(
            operation="disk-sharing", params=params, title="Update file sharing?",
            message="Your AirPort will restart to apply these settings. Connected disks will be briefly unavailable.",
            action_title="Update", risk="normal", summary="Update disk sharing settings",
            context={"host": connection.host}, presentation_id="disk-sharing.apply",
        ))
        require_request_acpd_ready(context, connection)
        require_request_no_disk_check(context, connection)
        context.stage("save_sharing")
        write_settings(connection, desired, current)
        moved = reboot_device(endpoint_host(connection.host), connection.password, wait=True,
                              callbacks=context.to_operation_callbacks(), ssh=connection)
        if moved:
            from dataclasses import replace
            connection = replace(connection, host=moved)
        context.stage("verify_sharing")
        actual = read_settings(connection)
        if actual.flags != desired.flags or actual.users != desired.users or actual.disk_password != desired.disk_password:
            raise SharingSettingsError("The AirPort restarted, but the sharing settings did not match. Reload them and try again.")
        return OperationResult(True, actual.public())
    except SharingSettingsError as error:
        message = str(error)
    raise AppOperationError(message, code="validation_failed")
