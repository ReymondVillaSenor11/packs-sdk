import type { ExecuteOptions } from './execution_helper';
import type { ExecuteSyncOptions } from './execution_helper';
import type { ExecutionContext } from '../api_types';
import type { MetadataContext } from '../api';
import type { MetadataFormula } from '../api';
import type { PackDefinition } from '../types';
import type { ParamDefs } from '../api_types';
import type { ParamValues } from '../api_types';
import type { SyncExecutionContext } from '../api_types';
export { ExecuteOptions } from './execution_helper';
export { ExecuteSyncOptions } from './execution_helper';
export interface ContextOptions {
    useRealFetcher?: boolean;
    credentialsFile?: string;
}
export declare function executeFormulaFromPackDef(packDef: PackDefinition, formulaNameWithNamespace: string, params: ParamValues<ParamDefs>, context?: ExecutionContext, options?: ExecuteOptions, { useRealFetcher, credentialsFile }?: ContextOptions): Promise<any>;
export declare function executeFormulaOrSyncFromCLI({ formulaName, params, manifestPath, vm, contextOptions, }: {
    formulaName: string;
    params: string[];
    manifestPath: string;
    vm?: boolean;
    contextOptions?: ContextOptions;
}): Promise<void>;
export declare function executeFormulaOrSyncWithVM({ formulaName, params, manifestPath, executionContext, }: {
    formulaName: string;
    params: ParamValues<ParamDefs>;
    manifestPath: string;
    executionContext?: SyncExecutionContext;
}): Promise<any>;
export declare function executeFormulaOrSyncWithRawParamsInVM({ formulaName, params: rawParams, manifestPath, executionContext, }: {
    formulaName: string;
    params: string[];
    manifestPath: string;
    executionContext?: SyncExecutionContext;
}): Promise<any>;
export declare function executeFormulaOrSyncWithRawParams({ formulaName, params: rawParams, module, executionContext, }: {
    formulaName: string;
    params: string[];
    module: any;
    vm?: boolean;
    executionContext: SyncExecutionContext;
}): Promise<any>;
export declare function executeSyncFormulaFromPackDef(packDef: PackDefinition, syncFormulaName: string, params: ParamValues<ParamDefs>, context?: SyncExecutionContext, options?: ExecuteSyncOptions, { useRealFetcher, credentialsFile }?: ContextOptions): Promise<any[]>;
export declare function executeMetadataFormula(formula: MetadataFormula, metadataParams?: {
    search?: string;
    formulaContext?: MetadataContext;
}, context?: ExecutionContext): Promise<any>;
