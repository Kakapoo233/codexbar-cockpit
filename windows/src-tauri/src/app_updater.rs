//! Automatic updates remain unavailable until the fork configures its own signed feed.
use serde::Serialize;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateMetadata {
    current_version: String,
}

#[tauri::command]
pub async fn check_cockpit_update(channel: String) -> Result<Option<UpdateMetadata>, String> {
    let _ = channel;
    Err("本项目尚未配置签名自动更新，请从项目发布页检查版本。 / Signed automatic updates are not configured for this fork.".into())
}
