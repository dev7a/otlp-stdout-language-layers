// Patch for full layer build - uses the configureExporterMap override
import { OTLPStdoutSpanExporter } from '@dev7a/otlp-stdout-span-exporter';

// Override configureExporterMap to add OTLP stdout exporter support
global.configureExporterMap = (exporterMap) => {
  console.log('[OTLP Stdout] Extending exporter map with otlpstdout');
  exporterMap.set('otlpstdout', () => new OTLPStdoutSpanExporter());
}; 