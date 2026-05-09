#!/usr/bin/env bats

# scaffold.bats — Validate OPC-IR plugin structure (M1.1)

@test "plugin.json exists and is valid JSON" {
  jq '.' .claude-plugin/plugin.json
}

@test "plugin.json has required fields" {
  name=$(jq -r '.name' .claude-plugin/plugin.json)
  [ "$name" = "opc-ir" ]

  version=$(jq -r '.version' .claude-plugin/plugin.json)
  [ -n "$version" ]

  description=$(jq -r '.description' .claude-plugin/plugin.json)
  [ ${#description} -gt 10 ]
}

@test "7 command files exist" {
  count=$(ls commands/opc-ir-*.md | wc -l | tr -d ' ')
  [ "$count" -eq 7 ]
}

@test "each command has YAML frontmatter with description >= 10 chars" {
  for cmd in commands/opc-ir-*.md; do
    # Extract frontmatter description
    desc=$(sed -n '/^---$/,/^---$/p' "$cmd" | grep 'description:' | sed 's/description: *//' | tr -d '"')
    [ ${#desc} -ge 10 ] || { echo "FAIL: $cmd description too short: '$desc'"; return 1; }
  done
}

@test "agent directory exists" {
  [ -d "agents" ]
}

@test "skill file exists" {
  [ -f "skills/opc-ir/skill.md" ]
}

@test "LICENSE file exists" {
  [ -f "LICENSE" ]
}

@test ".gitignore excludes runtime data" {
  grep -q '\.opc-ir' .gitignore || grep -q 'opc-ir' .gitignore
}
