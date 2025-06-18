# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Lightroom Classic plugin that integrates AI services (ChatGPT, Gemini, Ollama) to automatically generate metadata for photos including keywords, titles, captions, and alt text. The plugin has special support for soccer jersey detection and player identification.

## Key Architecture

### AI Provider System
- **AiModelAPI.lua**: Factory that creates appropriate AI provider instances
- Providers: ChatGptAPI, GeminiAPI, OllamaAPI, LmStudioAPI, AssistantAPI
- Each provider implements image analysis with different endpoints and authentication

### Photo Processing Workflows
1. **Single Image Analysis** (AnalyzeImageTask.lua):
   - Exports temp JPEG → AI analysis → writes metadata to catalog → deletes temp file
   - Adds hierarchical keywords to Lightroom catalog
   - Player keywords written using photo:addKeyword()

2. **Batch Processing** (BatchProcessor.lua):
   - Exports permanent JPEGs to AI_Staging folders
   - Creates burst folders with job.json files
   - No AI analysis - designed for external script processing
   - Embeds all metadata in exported JPEGs

### Soccer-Specific Features
- **PlayerRoster.lua**: Maps jersey numbers to player names
- **prompts/soccer-jersey-detection.txt**: Specialized prompt for jersey detection
- Hierarchical keyword structure: Fusion > 2016BN5 > [Player Name] > #[Number]

### Metadata Handling
- Keywords added to catalog with photo:addKeyword() 
- Title/caption/alt text written with photo:setRawMetadata()
- Export settings must include LR_embeddedMetadataOption = "all"
- Cannot use setRawMetadata() for keywords - causes "unknown metadata key" error

## Common Development Tasks

### Testing Photo Analysis
```bash
# Check logs for processing results
tail -f ~/Library/Logs/Adobe/Lightroom/LrClassicLogs/AIPlugin.log

# View Lightroom console errors
tail -f ~/Library/Application\ Support/Adobe/Lightroom/lrc_console.log
```

### Running Tests
```bash
# Test Ollama integration
cd test/
./ollama-test.sh

# Test with Python script
python ollama-test.py
```

### Key Configuration
All settings stored in Lightroom preferences (prefs):
- prefs.ai - Selected AI provider
- prefs.apiKey - API key for provider
- prefs.prompt - Analysis prompt template
- prefs.exportQuality - JPEG export quality (0-100)
- prefs.exportSize - Max dimension in pixels

## Important Notes

- The plugin requires Lightroom SDK 11.0+
- Jersey detection only works with specific numbers: 7, 10, 11, 19, 39, 64, 67, 68, 74, 76, 86, 90
- External scripts can read metadata from exported JPEGs but cannot write back to Lightroom catalog
- Batch processing is designed for one-way export to external workflows
- The inspect.lua module may have compatibility issues (compat53.module errors)