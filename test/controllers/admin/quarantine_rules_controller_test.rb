require "test_helper"

class Admin::QuarantineRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @gem_package = create(:gem_package, name: "rails")
    @rule = create(:quarantine_rule, :time_based, gem_package: @gem_package)
  end

  test "index returns success" do
    get admin_quarantine_rules_path
    assert_response :success
  end

  test "index displays quarantine rules" do
    get admin_quarantine_rules_path
    assert_select "td .badge", text: /Time Based/
  end

  test "index shows global rules" do
    create(:quarantine_rule, :global)

    get admin_quarantine_rules_path

    assert_select ".badge", text: /Global/
  end

  test "new returns success" do
    get new_admin_quarantine_rule_path
    assert_response :success
  end

  test "new displays form" do
    get new_admin_quarantine_rule_path

    assert_select "form"
    assert_select "select[name='quarantine_rule[rule_type]']"
    assert_select "select[name='quarantine_rule[gem_package_id]']"
  end

  test "create creates a new rule" do
    assert_difference "QuarantineRule.count", 1 do
      post admin_quarantine_rules_path, params: {
        quarantine_rule: {
          rule_type: "time_based",
          value: "48",
          enabled: true,
          description: "48-hour quarantine"
        }
      }
    end

    assert_redirected_to admin_quarantine_rules_path
    assert_equal "48", QuarantineRule.last.value
  end

  test "create with gem_package creates scoped rule" do
    post admin_quarantine_rules_path, params: {
      quarantine_rule: {
        gem_package_id: @gem_package.id,
        rule_type: "manual",
        enabled: true,
        description: "Manual rule for rails"
      }
    }

    assert_redirected_to admin_quarantine_rules_path
    assert_equal @gem_package.id, QuarantineRule.last.gem_package_id
  end

  test "create with invalid params renders new" do
    post admin_quarantine_rules_path, params: {
      quarantine_rule: {
        rule_type: nil
      }
    }

    assert_response :unprocessable_entity
  end

  test "edit returns success" do
    get edit_admin_quarantine_rule_path(@rule)
    assert_response :success
  end

  test "edit displays form with current values" do
    get edit_admin_quarantine_rule_path(@rule)

    assert_select "input[name='quarantine_rule[value]'][value='72']"
  end

  test "update modifies the rule" do
    patch admin_quarantine_rule_path(@rule), params: {
      quarantine_rule: {
        value: "96",
        description: "Updated description"
      }
    }

    assert_redirected_to admin_quarantine_rules_path
    @rule.reload
    assert_equal "96", @rule.value
    assert_equal "Updated description", @rule.description
  end

  test "update with invalid params renders edit" do
    patch admin_quarantine_rule_path(@rule), params: {
      quarantine_rule: {
        rule_type: nil
      }
    }

    assert_response :unprocessable_entity
  end

  test "destroy removes the rule" do
    assert_difference "QuarantineRule.count", -1 do
      delete admin_quarantine_rule_path(@rule)
    end

    assert_redirected_to admin_quarantine_rules_path
  end

  test "can disable a rule" do
    patch admin_quarantine_rule_path(@rule), params: {
      quarantine_rule: {
        enabled: false
      }
    }

    assert_redirected_to admin_quarantine_rules_path
    assert_not @rule.reload.enabled?
  end
end
