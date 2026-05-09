#!/usr/bin/env bats

# roles.bats — Validate role file counts and structure (M1.2)

@test "5 school roles exist" {
  count=$(find roles/_schools -name '*.md' | wc -l | tr -d ' ')
  [ "$count" -eq 5 ]
}

@test "2 advocate roles exist" {
  count=$(find roles/_advocates -name '*.md' | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]
}

@test "5 forecast strategist roles exist" {
  count=$(find roles/_forecast -name '*.md' | wc -l | tr -d ' ')
  [ "$count" -eq 5 ]
}

@test "each role has tags: array in frontmatter" {
  for role in roles/_schools/*.md roles/_advocates/*.md roles/_forecast/*.md; do
    bash tests/lib/check-frontmatter.sh "$role" tags || {
      echo "FAIL: $role missing tags"
      return 1
    }
  done
}

@test "school role names match spec" {
  for name in fundamental-analyst technical-analyst macro-economist quant-modeler behavioral-analyst; do
    [ -f "roles/_schools/$name.md" ] || { echo "Missing: roles/_schools/$name.md"; return 1; }
  done
}

@test "advocate role names match spec" {
  for name in bull-advocate bear-advocate; do
    [ -f "roles/_advocates/$name.md" ] || { echo "Missing: roles/_advocates/$name.md"; return 1; }
  done
}

@test "forecast strategist names match spec" {
  for name in macro-strategist cross-asset-allocator regime-detector historical-analogist contrarian-strategist; do
    [ -f "roles/_forecast/$name.md" ] || { echo "Missing: roles/_forecast/$name.md"; return 1; }
  done
}

@test "all defaults YAML files parse" {
  for f in defaults/*.yaml; do
    yq '.' "$f" > /dev/null || { echo "FAIL: $f does not parse"; return 1; }
  done
}

@test "role-weights.yaml has prior_weight 1.0 for all schools" {
  for school in fundamental-analyst technical-analyst macro-economist quant-modeler behavioral-analyst; do
    weight=$(yq ".schools[\"$school\"].prior_weight" defaults/role-weights.yaml)
    [ "$weight" = "1" ] || [ "$weight" = "1.0" ] || { echo "FAIL: $school prior=$weight"; return 1; }
  done
}

@test "role-weights.yaml has no posterior_weight (cold-start)" {
  # Should not contain posterior_weight key at all
  result=$(yq '.. | select(has("posterior_weight")) | .posterior_weight' defaults/role-weights.yaml 2>/dev/null || true)
  [ -z "$result" ] || { echo "FAIL: posterior_weight found in cold-start config"; return 1; }
}
