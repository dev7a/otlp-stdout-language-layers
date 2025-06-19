#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "boto3",
#     "click",
# ]
# ///
"""
Generate markdown release notes for OTLP stdout Lambda layers.
"""

import sys
import click
import boto3
from botocore.exceptions import ClientError
from typing import Dict, List, Optional


# Region to continent mapping
REGION_CONTINENTS = {
    "ca-central-1": "North America",
    "ca-west-1": "North America", 
    "us-east-1": "North America",
    "us-east-2": "North America",
    "us-west-2": "North America",
    "eu-central-1": "Europe",
    "eu-central-2": "Europe",
    "eu-north-1": "Europe",
    "eu-south-1": "Europe",
    "eu-south-2": "Europe",
    "eu-west-1": "Europe",
    "eu-west-2": "Europe",
    "eu-west-3": "Europe",
}

# Region display names
REGION_NAMES = {
    "ca-central-1": "Canada (Central)",
    "ca-west-1": "Canada (West)",
    "us-east-1": "US East (N. Virginia)", 
    "us-east-2": "US East (Ohio)",
    "us-west-2": "US West (Oregon)",
    "eu-central-1": "Europe (Frankfurt)",
    "eu-central-2": "Europe (Zurich)",
    "eu-north-1": "Europe (Stockholm)",
    "eu-south-1": "Europe (Milan)",
    "eu-south-2": "Europe (Spain)",
    "eu-west-1": "Europe (Ireland)",
    "eu-west-2": "Europe (London)",
    "eu-west-3": "Europe (Paris)",
}


def get_layer_arn(layer_name: str, region: str) -> Optional[str]:
    """Get the latest layer ARN for a given layer name and region."""
    try:
        lambda_client = boto3.client('lambda', region_name=region)
        # Get all versions and explicitly find the latest by version number
        response = lambda_client.list_layer_versions(LayerName=layer_name)
        
        if response['LayerVersions']:
            # Sort by version number descending to ensure we get the latest
            sorted_versions = sorted(
                response['LayerVersions'], 
                key=lambda x: x['Version'], 
                reverse=True
            )
            latest_version = sorted_versions[0]
            
            print(f"Found {len(response['LayerVersions'])} versions for {layer_name} in {region}, using version {latest_version['Version']}", file=sys.stderr)
            return latest_version['LayerVersionArn']
        return None
    except ClientError as e:
        print(f"Error getting layer version for {layer_name} in {region}: {e}", file=sys.stderr)
        return None


def collect_layer_data(layer_name: str, regions: List[str], account_id: str) -> Dict[str, Dict[str, str]]:
    """Collect layer data organized by continent and region."""
    continent_data = {}
    
    for region in regions:
        continent = REGION_CONTINENTS.get(region, "Other")
        
        if continent not in continent_data:
            continent_data[continent] = {}
            
        layer_arn = get_layer_arn(layer_name, region)
        continent_data[continent][region] = {
            'arn': layer_arn,
            'display_name': REGION_NAMES.get(region, region)
        }
    
    return continent_data


def generate_release_notes(
    language: str,
    upstream_version: str,
    exporter_version: str,
    release_group: str,
    regions: List[str],
    account_id: str,
    layer_name: str
) -> str:
    """Generate formatted release notes."""
    
    # Collect layer data
    continent_data = collect_layer_data(layer_name, regions, account_id)
    
    # Determine runtime
    runtime = "python3.13" if language == "python" else "nodejs22.x"
    
    # Generate release notes
    lines = []
    
    # Header and description
    lines.extend([
        f"## Release Details for {language} - Upstream {upstream_version}",
        "",
        "### Distribution Description",
        f"> OpenTelemetry Lambda Layer for {language} with OTLP stdout exporter",
        "> ",
        "> This layer provides automatic OpenTelemetry instrumentation for Lambda functions, sending traces to stdout in OTLP format for further processing by log-based telemetry systems.",
        "",
        "### Build Details",
        f"- **Upstream OpenTelemetry Lambda**: {upstream_version}",
        f"- **OTLP Stdout Exporter Version**: {exporter_version}",
        f"- **Release Group**: {release_group}",
        f"- **Runtime**: {runtime}",
        "",
        "<details><summary>",
        "",
        "### Layer ARNs by Region (click to expand)",
        "",
        "</summary>",
        ""
    ])
    
    # Generate tables by continent
    for continent in sorted(continent_data.keys()):
        lines.extend([
            "<table>",
            f'<tr><td colspan="2"><strong>{continent}</strong></td></tr>'
        ])
        
        # Process regions in this continent
        for region in sorted(continent_data[continent].keys()):
            region_info = continent_data[continent][region]
            region_display = region_info['display_name']
            arn = region_info['arn']
            
            # Create badge-safe region name
            region_badge_name = region.replace('-', '--')
            
            lines.extend([
                f'<tr><td colspan="2">✅ <strong>{region_display}</strong></td></tr>',
                '<tr>',
                f'<td><img src="https://img.shields.io/badge/{language}-{region_badge_name}-eee?style=for-the-badge" alt="{region}"></td>'
            ])
            
            if arn:
                lines.append(f'<td><code>{arn}</code></td>')
            else:
                lines.append('<td>❌ Layer not found or failed to publish</td>')
            
            lines.append('</tr>')
        
        lines.extend(['</table>', ''])
    
    # Add usage instructions
    exec_wrapper = "/opt/otel-instrument" if language == "python" else "/opt/otel-handler"
    
    # Find an example ARN to use in CloudFormation (prefer us-east-1, fallback to first available)
    example_arn = None
    if continent_data:
        # First try to find us-east-1
        for continent, regions in continent_data.items():
            if "us-east-1" in regions and regions["us-east-1"]["arn"]:
                example_arn = regions["us-east-1"]["arn"]
                break
        
        # If no us-east-1, use the first available ARN
        if not example_arn:
            for continent, regions in continent_data.items():
                for region, info in regions.items():
                    if info["arn"]:
                        example_arn = info["arn"]
                        break
                if example_arn:
                    break
    
    lines.extend([
        "",
        "</details>",
        "",
        "### Usage Instructions",
        "",
        "1. **Add the layer** to your Lambda function using one of the ARNs above",
        "2. **Set environment variables**:",
        f"   - `AWS_LAMBDA_EXEC_WRAPPER={exec_wrapper}`",
        "   - `OTEL_TRACES_EXPORTER=otlpstdout`",
        "3. **Configure your runtime** to process stdout logs containing OTLP trace data",
        "",
        "### Example CloudFormation",
        "",
        "```yaml",
        "MyLambdaFunction:",
        "  Type: AWS::Lambda::Function",
        "  Properties:",
        "    Layers:",
    ])
    
    if example_arn:
        lines.append(f'      - "{example_arn}"')
    else:
        lines.append('      - !Sub "arn:aws:lambda:${AWS::Region}:YOUR_ACCOUNT:layer:LAYER_NAME:VERSION"')
    
    lines.extend([
        "    Environment:",
        "      Variables:",
        f"        AWS_LAMBDA_EXEC_WRAPPER: {exec_wrapper}",
        "        OTEL_TRACES_EXPORTER: otlpstdout",
        "```",
        "",
    ])
    
    if example_arn:
        lines.append("> **Note**: The example above uses a specific ARN. For other regions, use the corresponding ARN from the table above.")
    else:
        lines.append("> **Note**: Replace `YOUR_ACCOUNT`, `LAYER_NAME`, and `VERSION` with the appropriate values from the ARNs above.")
    
    lines.append("")
    
    return "\n".join(lines)


@click.command()
@click.option(
    "--language",
    required=True,
    type=click.Choice(["python", "nodejs"]),
    help="Programming language for the layer"
)
@click.option(
    "--upstream-version", 
    required=True,
    help="Upstream OpenTelemetry Lambda version"
)
@click.option(
    "--exporter-version",
    required=True, 
    help="OTLP stdout exporter version"
)
@click.option(
    "--release-group",
    required=True,
    help="Release group (e.g., beta, prod, dev)"
)
@click.option(
    "--regions",
    required=True,
    help="Comma-separated list of AWS regions"
)
@click.option(
    "--account-id",
    help="AWS account ID (will be detected if not provided)"
)
@click.option(
    "--layer-name",
    required=True,
    help="Full layer name as published to AWS"
)
def main(language, upstream_version, exporter_version, release_group, regions, account_id, layer_name):
    """Generate GitHub Release notes for OTLP stdout Lambda layers."""
    
    # Parse regions
    regions_list = [r.strip() for r in regions.split(',')]
    
    # Get account ID if not provided
    if not account_id:
        try:
            sts_client = boto3.client('sts')
            account_id = sts_client.get_caller_identity()['Account']
        except ClientError as e:
            click.echo(f"Error: Could not determine AWS account ID: {e}", err=True)
            sys.exit(1)
    
    # Generate and output release notes
    notes = generate_release_notes(
        language=language,
        upstream_version=upstream_version,
        exporter_version=exporter_version,
        release_group=release_group,
        regions=regions_list,
        account_id=account_id,
        layer_name=layer_name
    )
    
    click.echo(notes)


if __name__ == "__main__":
    main() 