CSV2MRC
=======

Takes delimited text as input and outputs marc.

```
ruby csv2mrc.rb -i example.tsv -c example.json -o example.mrc --verbose
```

- By default input files are assumed to be tab delimited. 
- Multiple values in a single csv field are assumed to be semi-colon delimited

```
ruby csv2mrc.rb -i example.tsv -c example.json -o example.mrc --verbose --delimiter="," --split="|"
```

Configuration
-------------

The configuration file is a json document that specifies the marc mapping. [EXAMPLE](example.json)

**leader**

Set leader values. 

- The first three characters specify the control field (000 is the leader).
- The characters from the fourth position are byte positions (0 indexed).
- Ranges can be used i.e. 0087..10 is the 008 field year range.
- Values can be hard coded i.e. 0005: "n"
- Values can be a csv column i.e. "0087..10": "year", but must exist or will be ignored

**spec**

This is the primary mapping section. It's an array of csv column to marc field definitions. 

- The csv column headers are keys to a marc field definition
- Column headers as keys are repeatable so that a single column can be used in multiple marc fields
- The purpose of tag, ind1, ind2, and sub are obvious.
- The "join" key indicates that the subfield for this value should be appended to a matching field (by tag) if it exists    
- The "prepend" and "append" keys are used to wrap content to the csv value

**f_adds**

An array of hard / hand coded marc field definitions to be added to each record.

**s_adds**

An array of hard / hand coded subfields to add to all existing fields with matching tag if they exist. 

**protect**

A csv field can have multiple values (delimited). If the field should be non-repeatable protect will make all but the first value use an alternative tag.

**replace**

This can be used to replace any subfield value with another hard / hand coded value.

Example
-------

```
ruby csv2mrc.rb -i example.tsv -c example.json -o example.mrc --verbose
```

Output:

```
LEADER 00550nma  2200193   4500
008        2014                        eng  
022    $a 1234-5678 
040    $c test 
041    $a eng 
100 0  $a Cooper, Mark. 
245 10 $a Hello, Wine! / $c by Mark Cooper; Jon Haupt. 
260    $b Override publisher, $c 2014. 
490 0  $a IWRDB Journal. 
520    $a Editorial. 
650 04 $a Awesomeness. 
650 04 $a Wine. 
700 0  $a Haupt, Jon. 
773 0  $t IWRDB Journal. $g Vol. 1. No. 1. 2014. p. 1-5. $l 1 $q p. 1-5 $v 1 
856 42 $u http://iwrdb.org/123.html $y Link to article. 
LEADER 00574nma  2200181   4500
008        2014                        eng  
022    $a 1234-5678 
040    $c test 
041    $a eng 
100 0  $a Cooper, Mark. 
245 10 $a Why red wine is better than white / $c by Mark Cooper. 
260    $b Override publisher, $c 2014. 
490 0  $a IWRDB Journal. 
520    $a White wine is rubbish argues Mark Cooper ... 
650 04 $a Controversy. 
650 04 $a White wine. 
773 0  $t IWRDB Journal. $g Vol. 1. No. 1. 2014. p. 6-12. $l 1 $q p. 6-12 $v 1 
856 42 $u http://iwrdb.org/456.html $y Link to article. 
RECORDS PROCESSED       2
```

---
