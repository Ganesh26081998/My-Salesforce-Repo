/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : QuickBooksException
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : It creates a custom, specifically-named error type so your code can 
			    catch and display exact business errors (like "Location missing") instead of generic Salesforce system crashes.
----------------------------------------------------------------------------
*/

public class QuickBooksException extends Exception {}