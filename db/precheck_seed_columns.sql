-- Column existence pre-check for seed_appeal_scenarios.sql
SELECT t.tbl, t.col,
       CASE WHEN c.column_name IS NULL THEN '### MISSING ###' ELSE 'ok' END AS status
  FROM (VALUES
    ('packages','sr_number'),('packages','case_number'),('packages','yard'),
    ('packages','origin_country'),('packages','declared_value'),('packages','weight_kg'),
    ('packages','total_item_count'),('packages','description'),('packages','container_number'),
    ('packages','consignee_name'),('packages','consignee_nic'),('packages','consignee_address'),
    ('packages','consignee_phone'),('packages','declarant_name'),('packages','cusdec_no'),
    ('packages','cusdec_date'),('packages','entry_date'),('packages','reason'),
    ('packages','status'),('packages','inspected_by'),('packages','inspected_at'),
    ('package_items','yard'),('package_items','item_name'),('package_items','goods_description'),
    ('package_items','quantity'),('package_items','unit_of_measure'),('package_items','unit_value'),
    ('package_items','hs_code'),('package_items','category'),('package_items','is_prohibited'),
    ('package_items','status'),('package_items','reasons'),
    ('warehouse_entries','package_item_id'),('warehouse_entries','warehouse_id'),
    ('warehouse_entries','yard'),('warehouse_entries','zone'),('warehouse_entries','hold_reason'),
    ('warehouse_entries','item_count'),('warehouse_entries','admitted_by'),
    ('warehouse_entries','admitted_at'),('warehouse_entries','daily_rate'),
    ('warehouse_entries','is_returned'),('warehouse_entries','returned_at'),
    ('warehouse_entries','returned_by'),('warehouse_entries','return_notes'),
    ('forfeited_packages','item_id'),('forfeited_packages','entry_qty'),
    ('forfeited_packages','sr_number'),('forfeited_packages','consignee_name'),
    ('forfeited_packages','forfeited_at'),('forfeited_packages','appeal_deadline'),
    ('forfeited_packages','reason'),('forfeited_packages','yard'),
    ('forfeited_packages','source'),('forfeited_packages','appeal_hold'),
    ('forfeited_packages','appeal_hold_note'),('forfeited_packages','held_item_ids'),
    ('forfeited_packages','appeal_decision'),('forfeited_packages','appeal_decision_note'),
    ('forfeited_packages','appeal_decided_at'),('forfeited_packages','item_appeal_decisions')
  ) AS t(tbl,col)
  LEFT JOIN information_schema.columns c
         ON c.table_schema='public' AND c.table_name=t.tbl AND c.column_name=t.col
 WHERE c.column_name IS NULL
 ORDER BY 1,2;
