# 課題4: EC2上でDocker build用GitHub Actions runnerを動かす

GitHub Actionsの最初のjobでEC2を起動し、SSM経由でEC2を一時的なself-hosted runnerとして登録します。Docker buildとECR pushはEC2 runner上で実行し、最後のjobでEC2を停止します。

```text
GitHub Actions ubuntu-latest
  -> EC2 start
  -> SSMでephemeral self-hosted runner登録
  -> Docker build / pushをEC2で実行
  -> EC2 stop
```

## 構成

```text
aws-research-01-lightweight-runner/
  app/                 # Docker build対象
  infra/terraform/     # EC2 runner, ECR, VPC, SSM用IAM

.github/workflows/aws-research-01-lightweight-runner-ec2-docker-build.yml
```

## Terraform

GitHub Actions用のOIDC provider (`token.actions.githubusercontent.com`) は、リポジトリ直下のREADMEにある手順で作成済みである前提です。課題4のTerraformでは、そのOIDC providerを使う課題4専用Roleを作ります。

```bash
cd aws-research-01-lightweight-runner/infra/terraform
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Terraform apply後に次を確認します。

```bash
terraform output runner_instance_id
terraform output docker_build_ecr_repository_name
terraform output github_actions_role_arn
```

## GitHub Secrets / Variables

GitHub repositoryの `Settings > Secrets and variables > Actions` で設定します。

Secrets:

| Name | Value |
| --- | --- |
| `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_AWS_ROLE_TO_ASSUME` | `terraform output -raw github_actions_role_arn` |
| `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_GH_RUNNER_TOKEN` | self-hosted runner registration token作成用のGitHub token |

Variables:

| Name | Value |
| --- | --- |
| `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_AWS_REGION` | `ap-northeast-1` |
| `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_RUNNER_INSTANCE_ID` | `terraform output -raw runner_instance_id` |
| `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_ECR_REPOSITORY` | `terraform output -raw docker_build_ecr_repository_name` |

### `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_GH_RUNNER_TOKEN` の作成方法

ここで設定する値は、GitHub Actions runnerのregistration tokenそのものではなく、registration tokenをGitHub APIで作成するためのGitHub Personal Access Tokenです。

このworkflowでは、`Start EC2 runner` jobの中で次のAPIを呼び出して、一時的なself-hosted runner registration tokenを作成します。

```text
POST /repos/{owner}/{repo}/actions/runners/registration-token
```

そのため、`AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_GH_RUNNER_TOKEN` には、このAPIを実行できる権限を持つGitHub tokenを保存します。GitHub公式ドキュメント上、このrepository APIにはfine-grained personal access tokenの場合 `Administration` repository permissionの `write` が必要です。

#### fine-grained personal access tokenを作成する

GitHubの画面で次の順に進みます。

```text
右上のプロフィール画像
-> Settings
-> Developer settings
-> Personal access tokens
-> Fine-grained tokens
-> Generate new token
```

設定値:

| 項目 | 値 |
| --- | --- |
| Token name | `aws-research-01-lightweight-runner` など用途が分かる名前 |
| Expiration | 任意。長期運用する場合も期限を決め、期限切れ前に更新する |
| Resource owner | このrepositoryを所有しているuserまたはorganization |
| Repository access | `Only select repositories` |
| Selected repositories | このworkflowを置くrepository |
| Repository permissions > Administration | `Read and write` |

他のrepository permissionsは、この用途だけなら追加しません。

最後に `Generate token` を押し、表示されたtokenをコピーします。GitHubのPersonal Access Tokenは作成直後にしか完全な値を確認できません。あとからGitHub画面で再表示することはできないため、コピーし忘れた場合や値が分からなくなった場合は、既存tokenをregenerateするか、新しいtokenを作り直します。

#### tokenが正しいか確認する

ローカルでtokenを環境変数に入れて、registration token作成APIを試します。

```bash
export GH_RUNNER_PAT='github_pat_...'
export GITHUB_OWNER='your-owner'
export GITHUB_REPO='your-repo'

curl -fsSL \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GH_RUNNER_PAT}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/registration-token"
```

成功すると、次のように `token` と `expires_at` が返ります。

```json
{
  "token": "...",
  "expires_at": "2026-05-28T00:00:00Z"
}
```

このレスポンスに出る `token` は短命なregistration tokenです。GitHub Secretsに保存する値ではありません。GitHub Secretsに保存するのは、API呼び出しに使った `GH_RUNNER_PAT` の値です。

`403` や `404` が返る場合は、次を確認します。

| 確認項目 | 内容 |
| --- | --- |
| Resource owner | token作成時にrepositoryのownerを選んでいるか |
| Repository access | 対象repositoryが選択されているか |
| Administration | `Read and write` になっているか |
| organization approval | organization repositoryの場合、fine-grained tokenの利用承認が必要になっていないか |
| owner/repo | API URLのownerとrepository名が正しいか |

#### GitHub Secretに保存する

repositoryの画面で次の順に進みます。

```text
Settings
-> Secrets and variables
-> Actions
-> Secrets
-> New repository secret
```

次の値で登録します。

| 項目 | 値 |
| --- | --- |
| Name | `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_GH_RUNNER_TOKEN` |
| Secret | 作成したfine-grained personal access tokenの値 |

保存後、Secretの値はGitHub画面では確認できません。値を確認したい場合は、作成元のPersonal Access Token一覧でtoken名、期限、repository access、permissionsを確認します。token文字列そのものが不明な場合は、新しいtokenを作ってSecretを上書きします。

GitHub Actionsがすぐ失敗する場合は、失敗したrunを開いて `Start EC2 runner` jobのどのstepで落ちたか確認します。

よくある原因:

| 失敗step | 見直す値 |
| --- | --- |
| `Check required settings` | 上記Secrets / Variablesの名前と値 |
| `Configure AWS credentials` | `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_AWS_ROLE_TO_ASSUME`、OIDC provider、branch名 |
| `Start EC2 instance` | `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_RUNNER_INSTANCE_ID`、課題4用IAM RoleのEC2権限 |
| `Create GitHub runner registration token` | `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_GH_RUNNER_TOKEN` のrepository accessとAdministration write権限 |
| `Wait for SSM and runner bootstrap` | EC2のSSM online状態、public subnetの外向き通信、user data完了 |

`Start EC2 instance` で `UnauthorizedOperation` が出る場合は、課題4用GitHub Actions RoleのIAM policyがまだ更新されていません。Terraformを再applyしてから、GitHub Actionsを再実行します。

```bash
cd aws-research-01-lightweight-runner/infra/terraform
terraform apply
```

`Start EC2 instance` で `IncorrectInstanceState` が出る場合は、前回のworkflowでEC2が起動中、実行中、または停止中のまま次のrunを始めた状態です。workflowはEC2状態を確認し、`stopped` のときだけ起動するようにしています。

`Start EC2 instance` で `terminated` と出る場合は、GitHub Variable `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_RUNNER_INSTANCE_ID` が古いinstance IDを指しています。Terraform applyでEC2が作り直された後は、最新のoutputでGitHub Variableを更新します。

```bash
cd aws-research-01-lightweight-runner/infra/terraform
terraform output -raw runner_instance_id
```

GitHub repositoryの `Settings > Secrets and variables > Actions > Variables` で、`AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_RUNNER_INSTANCE_ID` を上の値に更新します。

`InvalidInstanceID.Malformed` が出る場合は、GitHub Variable `AWS_RESEARCH_01_LIGHTWEIGHT_RUNNER_RUNNER_INSTANCE_ID` に余計な文字が入っています。値は `i-` から始まるinstance IDだけにします。ターミナルで `terraform output -raw runner_instance_id` を実行したとき、末尾に `%` が見えることがありますが、これはzshの表示でinstance IDではありません。GitHub Variableには `%` を入れません。

`Wait for SSM and runner bootstrap` が `NOT_READY` のまま失敗する場合は、同じstepのログに `cloud_init_output_tail` が出ます。そこにEC2のuser data失敗理由が表示されます。

`runner_user_data.sh.tftpl` を変更した後は、EC2のuser dataを反映するために再applyします。この構成では `user_data_replace_on_change = true` にしているため、user data変更時はrunner用EC2が作り直されます。

```bash
cd aws-research-01-lightweight-runner/infra/terraform
terraform apply
```

## GitHub Actions実行

手動実行する場合:

```text
Actions -> Build Docker Image on EC2 Runner -> Run workflow
```

pushで実行される対象:

```text
aws-research-01-lightweight-runner/**
.github/workflows/aws-research-01-lightweight-runner-ec2-docker-build.yml
```

成功するとECRに次のタグがpushされます。

```text
<account_id>.dkr.ecr.ap-northeast-1.amazonaws.com/aws-research-01-lightweight-runner-docker-build:<github_sha>
<account_id>.dkr.ecr.ap-northeast-1.amazonaws.com/aws-research-01-lightweight-runner-docker-build:latest
```

## ローカルでDocker buildだけ確認

```bash
cd aws-research-01-lightweight-runner/app
docker build -t aws-research-01-lightweight-runner-local .
docker run --rm aws-research-01-lightweight-runner-local
```

期待される出力:

```text
aws-research-01-lightweight-runner Docker image built on an EC2-hosted GitHub Actions runner.
```
