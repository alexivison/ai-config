# Deploy Kubernetes Service

Deploy services to Kubernetes environments using ArgoCD/Kustomize overlays.

## Instructions

Use the `AskUserQuestion` tool to gather deployment configuration. Ask questions in logical groups to minimize back-and-forth.

### Step 1: Repository & Service Discovery

First, gather the basics:

1. **Repository path** (required): Absolute path to the repository containing Kubernetes manifests

2. **Service name** (required): Name of the service to deploy
   - Example: `my-api-service`, `user-service`

3. **Version** (required): Version tag to deploy
   - Example: `v1.0.6`, `v2.3.0`

### Step 2: Deployment Structure Discovery

After getting the repository path, **explore the directory structure** to understand the deployment layout:

```bash
# Look for common patterns
find {repo_path} -type d -name "kustomize" -o -name "overlays" -o -name "argocd" 2>/dev/null | head -20
```

Then ask the user to confirm or provide:

4. **Deployment path pattern**: Path pattern to the overlay directories
   - Common patterns:
     - `kubernetes/services/{service}/argocd/kustomize/overlays/{environment}/`
     - `kubernetes/services/{service}-{region}/argocd/kustomize/overlays/{environment}/`
     - `k8s/{service}/overlays/{environment}/`
   - Use `{service}`, `{region}`, `{environment}` as placeholders

5. **Regions** (optional): If the deployment uses regional directories
   - Example: `jp`, `us`, `eu`, or leave empty if not region-based

6. **Environments**: Available deployment environments
   - Example: `qa01`, `qa02`, `staging`, `production`
   - Ask which environment(s) to deploy to

### Step 3: Component Discovery

Explore the overlay directory to find deployment files:

```bash
# List deployment files in the overlay
find {resolved_overlay_path} -name "*.yaml" -o -name "*.yml" -o -name "*.env" 2>/dev/null
```

Then ask:

7. **Components to update**: Which files contain the image tags to update
   - Auto-suggest based on discovered files (e.g., `deployment.yaml`, `*-deployment.yaml`)
   - Let user confirm or modify the list

8. **Image tag field**: How the image tag is specified in the files
   - Common patterns: `image: repo/name:tag`, `newTag: tag`, `tag: tag`

## Deployment Steps

After gathering all inputs, perform the following:

1. **Verify the deployment path exists** for all region/environment combinations

2. **Search for PR templates** in the repository:
   ```bash
   # Look for PR templates in common locations
   find {repo_path} -type f \( -name "PULL_REQUEST_TEMPLATE*" -o -name "pull_request_template*" \) 2>/dev/null
   find {repo_path}/.github -type f -name "*.md" 2>/dev/null
   ```
   - Common locations: `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `docs/pull_request_template.md`
   - If found, read the template and use it as the base for the PR body
   - Fill in the template sections with deployment-specific information

3. **Update the image tags** in all specified component files
   - Search for the current tag pattern and replace with the new version

4. **Create a new branch** in the repository:
   ```bash
   cd {repo_path} && git checkout -b deploy-{service}-{environment}-{version}
   ```

5. **Stage and commit the changes**:
   ```bash
   cd {repo_path} && git add . && git commit -m "Deploy {service} {version} to {environment}"
   ```

6. **Push the branch** to origin:
   ```bash
   cd {repo_path} && git push -u origin deploy-{service}-{environment}-{version}
   ```

7. **Create a draft PR** using gh cli:
   - If a PR template was found in step 2, use it and fill in the relevant sections with deployment info
   - Otherwise, use this default format:
   ```bash
   cd {repo_path} && gh pr create --draft --title "Deploy {service} {version} to {environment}" --body "$(cat <<'EOF'
   ## What

   Update {service} container image to {version} in {environment}

   Updated components:
   - [list the components updated]

   ## Why

   Deploy {version} release to {environment}

   ## References

   - (Add any relevant PR or ticket references)
   EOF
   )"
   ```

8. **Output the PR URL** after successful creation

## Tips

- If deploying to multiple environments, ask if user wants separate PRs or one combined PR
- For regional deployments, confirm all regions should get the same version
- Always show a summary of changes before committing
