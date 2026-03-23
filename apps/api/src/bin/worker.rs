#[tokio::main]
async fn main() -> anyhow::Result<()> {
    brijyatra_api::run_worker().await
}
