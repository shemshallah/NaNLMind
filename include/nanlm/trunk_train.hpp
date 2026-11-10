#pragma once
namespace nanlm {
int trunk_train_cli(int argc, char** argv);
int hier_train_cli(int argc, char** argv);
int context_train_cli(int argc, char** argv);
int phase_ingest_cli(int argc, char** argv);
int phase_train_cli(int argc, char** argv);
int phase_codebook_cli(int argc, char** argv);
int meta_tokenize_cli(int argc, char** argv);
int temporal_tokenize_cli(int argc, char** argv);
int ngram_train_cli(int argc, char** argv);
int context_hash_check_cli(int argc, char** argv);
}
