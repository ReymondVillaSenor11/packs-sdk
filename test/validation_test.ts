import {testHelper} from './test_helper';
import {FakePack} from './test_utils';
import type {ParamDefs} from 'api_types';
import type {StringSchema} from '../schema';
import {ValueType} from '../schema';
import {coerceParams} from '../testing/coercion';
import {createFakePack} from './test_utils';
import {executeFormulaFromPackDef} from '../testing/execution';
import {executeSyncFormulaFromPackDef} from '../testing/execution';
import {makeBooleanParameter} from '../api';
import {makeNumericParameter} from '../api';
import {makeObjectFormula} from '../api';
import {makeObjectSchema} from '../schema';
import {makeStringArrayParameter} from '../api';
import {makeStringFormula} from '../api';
import {makeStringParameter} from '../api';
import {makeSyncTable} from '../api';

describe('Property validation in objects', () => {
  const fakeSchema = makeObjectSchema({
    type: ValueType.Object,
    primary: 'date',
    id: 'date',
    properties: {
      bool: {type: ValueType.Boolean},
      date: {type: ValueType.String, codaType: ValueType.Date},
      url: {type: ValueType.String, codaType: ValueType.Url},
      slider: {
        type: ValueType.Number,
        codaType: ValueType.Slider,
        minimum: 12,
        maximum: 30,
        step: 3,
      },
      scale: {
        type: ValueType.Number,
        codaType: ValueType.Scale,
        maximum: 5,
      },
      names: {type: ValueType.Array, items: {type: ValueType.String} as StringSchema},
      person: {
        type: ValueType.Object,
        codaType: ValueType.Person,
        id: 'email',
        properties: {email: {type: ValueType.String}},
      },
      ref: {
        type: ValueType.Object,
        codaType: ValueType.Reference,
        id: 'reference',
        properties: {
          reference: {
            type: ValueType.Object,
            properties: {
              objectId: {type: ValueType.String},
              identifier: {type: ValueType.String},
              name: {type: ValueType.String},
            },
          },
        },
      },
      nested: {
        type: ValueType.Object,
        id: 'string',
        properties: {
          string: {type: ValueType.String},
          number: {type: ValueType.Number},
        },
      },
    },
    identity: {packId: FakePack.id, name: 'Events'},
  });

  const fakeBooleanFormula = makeObjectFormula({
    name: 'Boolean',
    description: 'Returns the boolean you passed in.',
    examples: [],
    parameters: [makeBooleanParameter('boolParam', 'Pass in a boolean (malformed is ok)')],
    execute: async ([boolParam]) => {
      return {bool: boolParam};
    },
    response: {
      schema: fakeSchema,
    },
  });

  const fakeDateFormula = makeObjectFormula({
    name: 'Date',
    description: 'Returns the dateString you passed in.',
    examples: [],
    parameters: [makeStringParameter('dateParam', 'Pass in a date (malformed is ok)')],
    execute: async ([dateParam]) => {
      return {date: dateParam};
    },
    response: {
      schema: fakeSchema,
    },
  });

  const fakeSliderFormula = makeObjectFormula({
    name: 'Slider',
    description: 'Returns the number you passed in.',
    examples: [],
    parameters: [makeNumericParameter('number', 'Pass in a number (malformed is ok)')],
    execute: async ([numberParam]) => {
      return {slider: numberParam};
    },
    response: {
      schema: fakeSchema,
    },
  });

  const fakeScaleFormula = makeObjectFormula({
    name: 'Scale',
    description: 'Returns the number you passed in.',
    examples: [],
    parameters: [makeNumericParameter('number', 'Pass in a number (malformed is ok)')],
    execute: async ([numberParam]) => {
      return {scale: numberParam};
    },
    response: {
      schema: fakeSchema,
    },
  });

  const fakeUrlFormula = makeObjectFormula({
    name: 'Url',
    description: 'Returns the string you passed in.',
    examples: [],
    parameters: [makeStringParameter('string', 'Pass in a string (malformed is ok)')],
    execute: async ([stringParam]) => {
      return {url: stringParam};
    },
    response: {
      schema: fakeSchema,
    },
  });

  const fakeArrayFormula = makeObjectFormula({
    name: 'GetNames',
    description: 'Returns the names you passed in.',
    examples: [],
    parameters: [makeStringArrayParameter('string', 'Pass in an array of strings')],
    execute: async ([stringArray]) => {
      return {names: stringArray};
    },
    response: {
      schema: fakeSchema,
    },
  });

  const fakePeopleFormula = makeObjectFormula({
    name: 'GetPerson',
    description: 'Returns the person you passed in.',
    examples: [],
    parameters: [
      makeStringParameter('email', 'Pass in a string'),
      makeBooleanParameter('returnMalformed', 'whether or not to return a malformed response'),
    ],
    execute: async ([email, malformed]) => {
      return malformed ? {person: {emailAddress: email}} : {person: {email}};
    },
    response: {
      schema: fakeSchema,
    },
  });

  const fakeNestedObjectFormula = makeObjectFormula({
    name: 'GetNestedObject',
    description: 'Returns an object with an object inside.',
    examples: [],
    parameters: [makeBooleanParameter('returnMalformed', 'whether or not to return a malformed response')],
    execute: async ([malformed]) => {
      return {nested: {string: 'foo', number: malformed ? '123' : 123}};
    },
    response: {
      schema: fakeSchema,
    },
  });

  const fakePack = createFakePack({
    formulas: {
      Fake: [
        fakeBooleanFormula,
        fakeDateFormula,
        fakeSliderFormula,
        fakeScaleFormula,
        fakeUrlFormula,
        fakeArrayFormula,
        fakePeopleFormula,
        fakeNestedObjectFormula,
      ],
    },
  });

  it('validates boolean', async () => {
    await executeFormulaFromPackDef(fakePack, 'Fake::Boolean', [true]);
  });

  it('validates correct date string', async () => {
    await executeFormulaFromPackDef(fakePack, 'Fake::Date', ['Wed, 02 Oct 2002 15:00:00 +0200']);
  });

  it('throws on malformed date string', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::Date', ['asdfdasf']),
      /The following errors were found when validating the result of the formula "Date":\nFailed to parse asdfdasf as a date./,
    );
  });

  it('validates correct slider value', async () => {
    await executeFormulaFromPackDef(fakePack, 'Fake::Slider', [15]);
  });

  it('rejects non-numeric slider value', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::Slider', ['9']),
      /The following errors were found when validating the result of the formula "Slider":\nExpected a number property for Slider but got "9"./,
    );
  });

  it('rejects slider value below minimum', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::Slider', [9]),
      /The following errors were found when validating the result of the formula "Slider":\nSlider value 9 is below the specified minimum value of 12./,
    );
  });

  it('rejects slider value above maximum', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::Slider', [32]),
      /The following errors were found when validating the result of the formula "Slider":\nSlider value 32 is greater than the specified maximum value of 30./,
    );
  });

  it('validates correct scale value', async () => {
    await executeFormulaFromPackDef(fakePack, 'Fake::Scale', [4]);
  });

  it('rejects scale value below 0', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::Scale', [-1]),
      /The following errors were found when validating the result of the formula "Scale":\nScale value -1 cannot be below 0./,
    );
  });

  it('rejects scale value above maximum', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::Scale', [6]),
      /The following errors were found when validating the result of the formula "Scale":\nScale value 6 is greater than the specified maximum value of 5./,
    );
  });

  it('validates properly formatted url', async () => {
    await executeFormulaFromPackDef(fakePack, 'Fake::Url', ['http://google.com']);
  });

  it('rejects improperly formatted url', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::Url', ['mailto:http://google.com']),
      /The following errors were found when validating the result of the formula "Url":\nProperty with codaType "url" must be a valid HTTP\(S\) url, but got "mailto:http:\/\/google.com"./,
    );
  });

  it('rejects garbage url', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::Url', ['jasiofjsdofjiaof']),
      /The following errors were found when validating the result of the formula "Url":\nProperty with codaType "url" must be a valid HTTP\(S\) url, but got "jasiofjsdofjiaof"./,
    );
  });

  it('rejects person with no id field', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::GetPerson', ['test@coda.io', true]),
      /The following errors were found when validating the result of the formula "GetPerson":\nCodatype person is missing required field "Email"./,
    );
  });

  it('rejects person with non-email id', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::GetPerson', ['notanemail', false]),
      /The following errors were found when validating the result of the formula "GetPerson":\nThe id field for the person result must be an email string, but got "notanemail"./,
    );
  });

  it('validates correct person reference', async () => {
    await executeFormulaFromPackDef(fakePack, 'Fake::GetPerson', ['test@coda.io', false]);
  });

  it('rejects nested object with incorrect nested type', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::GetNestedObject', [true]),
      /The following errors were found when validating the result of the formula "GetNestedObject":\nExpected a number property for Nested.Number but got "123"./,
    );
  });

  it('validates string array', async () => {
    await executeFormulaFromPackDef(fakePack, 'Fake::GetNames', [['Jack', 'Jill', 'Hill']]);
  });

  it('rejects non array', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::GetNames', ['Jack']),
      /The following errors were found when validating the result of the formula "GetNames":\nExpected an array result but got Jack./,
    );
  });

  it('rejects bad array items', async () => {
    await testHelper.willBeRejectedWith(
      executeFormulaFromPackDef(fakePack, 'Fake::GetNames', [['Jack', 'Jill', 123, true]]),
      /The following errors were found when validating the result of the formula "GetNames":\nExpected a string property for Names\[2\] but got 123.\nExpected a string property for Names\[3\] but got true./,
    );
  });
});

describe('validation in sync tables', () => {
  const fakePersonSchema = makeObjectSchema({
    type: ValueType.Object,
    primary: 'name',
    id: 'name',
    properties: {
      name: {type: ValueType.String},
      info: {
        type: ValueType.Object,
        properties: {
          age: {type: ValueType.Number},
          grade: {type: ValueType.Number},
        },
      },
    },
    identity: {packId: FakePack.id, name: 'Person'},
  });

  const fakePack = createFakePack({
    syncTables: [
      makeSyncTable('Classes', fakePersonSchema, {
        name: 'Students',
        description: 'Gets students in a class',
        execute: async ([malformed], context) => {
          const {continuation} = context.sync;
          const page = continuation?.page;
          switch (page) {
            case 1:
            case undefined:
              return {
                result: [
                  {name: 'Alice', info: {age: malformed ? '100' : 100, grade: 1}},
                  {name: 'Bob', info: {age: 100, grade: 1}},
                ],
                continuation: {page: 2},
              } as any;
            case 2:
              return {
                result: [
                  {name: 'Chris', info: {age: 100, grade: 1}},
                  {name: 'Diana', info: {age: 100, grade: 1}},
                ],
              };
            default:
              return {
                result: [],
              };
          }
        },
        network: {hasSideEffect: false},
        parameters: [makeBooleanParameter('malformed', 'whether or not to return a malformed response')],
        examples: [],
      }),
    ],
  });

  it('rejects bad nested object property for item in sync formula', async () => {
    await testHelper.willBeRejectedWith(
      executeSyncFormulaFromPackDef(fakePack, 'Students', [true]),
      /Expected a number property for Students\[0\].Info.Age but got "100"./,
    );
  });

  it('validates correct items in sync formula', async () => {
    await executeSyncFormulaFromPackDef(fakePack, 'Students', [false]);
  });
});

describe('param validation', () => {
  function makeFormula(parameters: ParamDefs, varargParameters?: ParamDefs) {
    return makeStringFormula({
      name: 'Fake',
      description: '',
      examples: [],
      execute: async _params => {
        return 'ok';
      },
      parameters,
      varargParameters,
    });
  }

  describe('coercion', () => {
    it('basic', () => {
      const formula = makeFormula([
        makeNumericParameter('num', ''),
        makeBooleanParameter('bool', ''),
        makeStringParameter('string', ''),
      ]);
      const coerced = coerceParams(formula, ['-5', 'true', '123']);
      assert.deepEqual(coerced, [-5, true, '123']);
    });

    it('excess params tolerated', () => {
      const formula = makeFormula([
        makeNumericParameter('num', ''),
        makeBooleanParameter('bool', ''),
        makeStringParameter('string', ''),
      ]);
      const coerced = coerceParams(formula, ['-5', 'true', '123', 'foo', 'bar']);
      assert.deepEqual(coerced, [-5, true, '123', 'foo', 'bar']);
    });

    it('varargs', () => {
      const formula = makeFormula(
        [makeBooleanParameter('bool', '')],
        [makeNumericParameter('num', ''), makeStringParameter('string', '')],
      );
      const coerced = coerceParams(formula, ['false', '2.2', 'foo', '-18', '123']);
      assert.deepEqual(coerced, [false, 2.2, 'foo', -18, '123']);
    });
  });
});
