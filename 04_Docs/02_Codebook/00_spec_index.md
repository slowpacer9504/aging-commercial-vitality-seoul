# Research Specification Index

This document serves as the central hub for core specifications to reference during coding. The current active contract is the **Seoul administrative dong quarterly panel (`adm_cd x yq`)**.

Implementation scripts follow a role-based folder structure and a folder-local numbering system. The canonical dataset, key, timing, and output naming conventions to be interpreted strictly follow the quarterly contract declared in this codebook.

## Base Design Documents

- [research_plan.md](../01_Design/research_plan.md)
- [research_procedure.md](../01_Design/research_procedure.md)
- [r_code_style_guide.md](../01_Design/r_code_style_guide.md)
- [file_tree.md](../01_Design/file_tree.md)

## Execution Templates

- `00_template_preprocessing_aging_commerce.R`
- `00_template_modeling_aging_commerce.R`

## Specification Documents

1. [01_data_spec.md](./01_data_spec.md) (Companion dataset list: `01_data_spec_datasets.csv`)
2. [02_variable_dictionary.md](./02_variable_dictionary.md) (Companion variable dictionary table: `02_variable_dictionary.csv`)
3. [03_join_harmonization_rules.md](./03_join_harmonization_rules.md) (Companion join/harmonization rules: `03_join_harmonization_rules.csv`)
4. [04_model_spec.md](./04_model_spec.md) (Companion model specs: `04_model_spec.csv`)
5. `99_spec_to_code_map.csv`

## Quick Reference Sequence

1. Review data layers, output locations, and QC logs: [01_data_spec.md](./01_data_spec.md) and `01_data_spec_datasets.csv`
2. Check variable definitions and quarterly publication/as-of rules: [02_variable_dictionary.md](./02_variable_dictionary.md) and `02_variable_dictionary.csv`
3. Verify join keys and harmonization rules: [03_join_harmonization_rules.md](./03_join_harmonization_rules.md) and `03_join_harmonization_rules.csv`
4. Confirm model specifications, FEs, timing, and output contracts: [04_model_spec.md](./04_model_spec.md) and `04_model_spec.csv`
5. Check actual script mappings: `99_spec_to_code_map.csv`
