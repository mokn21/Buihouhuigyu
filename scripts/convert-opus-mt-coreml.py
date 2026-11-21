#!/usr/bin/env python3
"""Export a MarianMT English->Arabic checkpoint as fixed-shape Core ML programs.

The Swift runtime calls the encoder once, then calls the decoder for each greedy
step. Fixed shapes keep the export deterministic for the first integration.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import torch
from transformers import MarianMTModel, MarianTokenizer
import coremltools as ct


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', default='Helsinki-NLP/opus-mt-tc-big-en-ar')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--max-input-tokens', type=int, default=64)
    parser.add_argument('--max-output-tokens', type=int, default=64)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    tokenizer = MarianTokenizer.from_pretrained(args.model)
    tokenizer.save_pretrained(args.output)
    model = MarianMTModel.from_pretrained(args.model).eval()
    model.config.use_cache = False

    input_ids = torch.ones((1, args.max_input_tokens), dtype=torch.int32)
    attention_mask = torch.ones((1, args.max_input_tokens), dtype=torch.int32)

    class Encoder(torch.nn.Module):
        def __init__(self, base):
            super().__init__()
            self.base = base
        def forward(self, input_ids, attention_mask):
            return self.base.model.encoder(
                input_ids=input_ids.to(torch.long),
                attention_mask=attention_mask.to(torch.long),
                return_dict=False,
            )[0]

    class Decoder(torch.nn.Module):
        def __init__(self, base):
            super().__init__()
            self.base = base
        def forward(self, decoder_input_ids, encoder_hidden_states, encoder_attention_mask):
            outputs = self.base.model.decoder(
                input_ids=decoder_input_ids.to(torch.long),
                attention_mask=torch.ones_like(decoder_input_ids, dtype=torch.long),
                encoder_hidden_states=encoder_hidden_states,
                encoder_attention_mask=encoder_attention_mask.to(torch.long),
                use_cache=False,
                return_dict=False,
            )[0]
            return self.base.lm_head(outputs)

    encoder = torch.jit.trace(Encoder(model), (input_ids, attention_mask), strict=False)
    decoder_ids = torch.ones((1, args.max_output_tokens), dtype=torch.int32)
    hidden = torch.zeros((1, args.max_input_tokens, model.config.d_model), dtype=torch.float32)
    decoder_mask = torch.ones((1, args.max_input_tokens), dtype=torch.int32)
    decoder = torch.jit.trace(Decoder(model), (decoder_ids, hidden, decoder_mask), strict=False)

    deployment = ct.target.iOS18
    encoder_ml = ct.convert(
        encoder,
        convert_to='mlprogram',
        minimum_deployment_target=deployment,
        inputs=[
            ct.TensorType(name='input_ids', shape=input_ids.shape, dtype=int),
            ct.TensorType(name='attention_mask', shape=attention_mask.shape, dtype=int),
        ],
        outputs=[ct.TensorType(name='encoder_hidden_states')],
    )
    encoder_ml.author = 'Helsinki-NLP / Orion Subtitles integration'
    encoder_ml.short_description = 'OPUS-MT English-Arabic encoder'
    encoder_ml.save(str(args.output / 'OpusMTEnglishArabicEncoder.mlpackage'))

    decoder_ml = ct.convert(
        decoder,
        convert_to='mlprogram',
        minimum_deployment_target=deployment,
        inputs=[
            ct.TensorType(name='decoder_input_ids', shape=decoder_ids.shape, dtype=int),
            ct.TensorType(name='encoder_hidden_states', shape=hidden.shape),
            ct.TensorType(name='encoder_attention_mask', shape=decoder_mask.shape, dtype=int),
        ],
        outputs=[ct.TensorType(name='logits')],
    )
    decoder_ml.author = 'Helsinki-NLP / Orion Subtitles integration'
    decoder_ml.short_description = 'OPUS-MT English-Arabic decoder'
    decoder_ml.save(str(args.output / 'OpusMTEnglishArabicDecoder.mlpackage'))

    (args.output / 'model-metadata.txt').write_text(
        f'model={args.model}\n'
        f'max_input_tokens={args.max_input_tokens}\n'
        f'max_output_tokens={args.max_output_tokens}\n'
        f'pad_token_id={tokenizer.pad_token_id}\n'
        f'eos_token_id={tokenizer.eos_token_id}\n'
        f'decoder_start_token_id={model.config.decoder_start_token_id}\n',
        encoding='utf-8',
    )


if __name__ == '__main__':
    main()
